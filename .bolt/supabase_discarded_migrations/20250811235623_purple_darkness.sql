/*
  # Corrigir sistema de expiração de cashback

  1. Funções
    - Criar função para limpar cashbacks expirados automaticamente
    - Atualizar view de saldos para nunca retornar valores negativos
    - Adicionar função para executar limpeza mensal

  2. Segurança
    - Garantir que saldos nunca sejam negativos
    - Limpar transações expiradas automaticamente
*/

-- Função para limpar cashbacks expirados
CREATE OR REPLACE FUNCTION clean_expired_cashback()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Marcar transações de cashback como expiradas
  UPDATE transactions 
  SET status = 'expired',
      updated_at = now()
  WHERE type = 'purchase' 
    AND status = 'approved'
    AND expires_at < now()
    AND expires_at IS NOT NULL;
    
  -- Log da limpeza
  INSERT INTO pdv_error_logs (error_message, error_data)
  VALUES (
    'Limpeza automática de cashback expirado executada',
    jsonb_build_object(
      'timestamp', now(),
      'action', 'clean_expired_cashback'
    )
  );
END;
$$;

-- Função para recalcular saldo disponível (sempre positivo)
CREATE OR REPLACE FUNCTION get_customer_available_balance(customer_uuid uuid)
RETURNS numeric
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  balance_result numeric := 0;
BEGIN
  -- Somar cashback de compras aprovadas não expiradas
  SELECT COALESCE(SUM(cashback_amount), 0)
  INTO balance_result
  FROM transactions
  WHERE customer_id = customer_uuid
    AND type = 'purchase'
    AND status = 'approved'
    AND (expires_at IS NULL OR expires_at > now());
    
  -- Subtrair resgates aprovados
  balance_result := balance_result - COALESCE((
    SELECT SUM(amount)
    FROM transactions
    WHERE customer_id = customer_uuid
      AND type = 'redemption'
      AND status = 'approved'
  ), 0);
  
  -- Garantir que nunca seja negativo
  RETURN GREATEST(balance_result, 0);
END;
$$;

-- Atualizar view de saldos para usar a nova função
DROP VIEW IF EXISTS customer_balances;

CREATE VIEW customer_balances AS
SELECT 
  c.id as customer_id,
  c.name,
  get_customer_available_balance(c.id) as available_balance,
  (
    SELECT cashback_amount
    FROM transactions t
    WHERE t.customer_id = c.id
      AND t.type = 'purchase'
      AND t.status = 'approved'
      AND t.expires_at IS NOT NULL
      AND t.expires_at > now()
    ORDER BY t.expires_at ASC
    LIMIT 1
  ) as expiring_amount,
  (
    SELECT expires_at
    FROM transactions t
    WHERE t.customer_id = c.id
      AND t.type = 'purchase'
      AND t.status = 'approved'
      AND t.expires_at IS NOT NULL
      AND t.expires_at > now()
    ORDER BY t.expires_at ASC
    LIMIT 1
  ) as expiration_date
FROM customers c;

-- Função para executar limpeza mensal automaticamente
CREATE OR REPLACE FUNCTION monthly_cashback_cleanup()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Executar limpeza de cashbacks expirados
  PERFORM clean_expired_cashback();
  
  -- Log da execução mensal
  INSERT INTO pdv_error_logs (error_message, error_data)
  VALUES (
    'Limpeza mensal de cashback executada',
    jsonb_build_object(
      'timestamp', now(),
      'month', EXTRACT(month FROM now()),
      'year', EXTRACT(year FROM now())
    )
  );
END;
$$;

-- Atualizar função de validação de resgate para usar saldo calculado
CREATE OR REPLACE FUNCTION validate_redemption()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  available_balance numeric;
BEGIN
  -- Só validar para resgates
  IF NEW.type != 'redemption' THEN
    RETURN NEW;
  END IF;
  
  -- Obter saldo disponível usando a nova função
  available_balance := get_customer_available_balance(NEW.customer_id);
  
  -- Verificar se há saldo suficiente
  IF available_balance < NEW.amount THEN
    RAISE EXCEPTION 'Saldo insuficiente para resgate. Disponível: R$ %, Solicitado: R$ %', 
      available_balance, NEW.amount;
  END IF;
  
  RETURN NEW;
END;
$$;

-- Criar índices para melhor performance
CREATE INDEX IF NOT EXISTS idx_transactions_expiration_check 
ON transactions (customer_id, type, status, expires_at) 
WHERE type = 'purchase' AND status = 'approved';

-- Executar limpeza inicial
SELECT clean_expired_cashback();