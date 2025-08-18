-- Drop existing trigger first
DROP TRIGGER IF EXISTS trg_handle_balance ON transactions;

-- Drop existing functions
DROP FUNCTION IF EXISTS get_available_balance(uuid);
DROP FUNCTION IF EXISTS handle_customer_balance();

-- Create improved available balance function with strict decimal handling
CREATE OR REPLACE FUNCTION get_available_balance(p_customer_id uuid)
RETURNS decimal AS $$
DECLARE
  v_available_cashback decimal;
  v_used_redemptions decimal;
  v_final_balance decimal;
BEGIN
  -- Get sum of valid cashback with explicit casting and rounding
  SELECT COALESCE(SUM(cashback_amount::numeric), 0)::decimal
  INTO v_available_cashback
  FROM transactions
  WHERE customer_id = p_customer_id
    AND type = 'purchase'
    AND status = 'approved'
    AND expires_at > CURRENT_TIMESTAMP;

  -- Get sum of approved redemptions with explicit casting
  SELECT COALESCE(SUM(amount::numeric), 0)::decimal
  INTO v_used_redemptions
  FROM transactions
  WHERE customer_id = p_customer_id
    AND type = 'redemption'
    AND status = 'approved';

  -- Calculate final balance with proper decimal handling
  v_final_balance := v_available_cashback - v_used_redemptions;
  
  -- Debug logging
  RAISE NOTICE 'Balance calculation for customer %:
    Available cashback (before rounding): %
    Used redemptions (before rounding): %
    Final balance (before rounding): %',
    p_customer_id,
    v_available_cashback,
    v_used_redemptions,
    v_final_balance;
  
  RETURN GREATEST(v_final_balance, 0);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create improved balance handling function
CREATE OR REPLACE FUNCTION handle_customer_balance()
RETURNS TRIGGER AS $$
DECLARE
  v_available_balance decimal;
  v_expired_balance decimal;
BEGIN
  -- For redemptions, verify balance is sufficient
  IF TG_OP IN ('INSERT', 'UPDATE') AND 
     NEW.type = 'redemption' AND 
     NEW.status = 'approved' THEN
    
    -- Get available balance excluding current redemption
    SELECT get_available_balance(NEW.customer_id) INTO v_available_balance;

    -- Get expired balance
    SELECT COALESCE(SUM(cashback_amount::numeric), 0)::decimal
    INTO v_expired_balance
    FROM transactions
    WHERE customer_id = NEW.customer_id
      AND type = 'purchase'
      AND status = 'approved'
      AND expires_at <= CURRENT_TIMESTAMP;

    -- Debug logging
    RAISE NOTICE 'Redemption validation:
      Customer ID: %
      Requested amount: %
      Available balance: %
      Expired balance: %',
      NEW.customer_id,
      NEW.amount,
      v_available_balance,
      v_expired_balance;

    -- Compare values directly without additional rounding
    IF v_available_balance < NEW.amount THEN
      IF v_expired_balance > 0 THEN
        RAISE EXCEPTION 'Você possui R$ % em cashback expirado. Saldo disponível para resgate: R$ %',
          v_expired_balance,
          v_available_balance;
      ELSE
        RAISE EXCEPTION 'Saldo insuficiente para resgate. Disponível: R$ %',
          v_available_balance;
      END IF;
    END IF;
  END IF;

  -- Update customer balance
  UPDATE customers c
  SET balance = get_available_balance(c.id),
      updated_at = NOW()
  WHERE id = COALESCE(NEW.customer_id, OLD.customer_id);

  RETURN CASE TG_OP
    WHEN 'DELETE' THEN OLD
    ELSE NEW
  END;
END;
$$ LANGUAGE plpgsql;

-- Create trigger
CREATE TRIGGER trg_handle_balance
  AFTER INSERT OR UPDATE OR DELETE ON transactions
  FOR EACH ROW
  EXECUTE FUNCTION handle_customer_balance();

-- Add comments
COMMENT ON FUNCTION get_available_balance IS 'Calculates available balance with strict decimal handling';
COMMENT ON FUNCTION handle_customer_balance IS 'Handles balance updates and validates redemptions with improved precision';

-- Update all customer balances
UPDATE customers c
SET balance = get_available_balance(c.id),
    updated_at = NOW();