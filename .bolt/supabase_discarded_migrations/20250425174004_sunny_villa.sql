/*
  # Fix balance calculation functions

  1. Changes
    - Fix get_available_balance to properly handle redemptions
    - Add debug logging for balance calculations
    - Improve error messages
*/

-- Update get_available_balance function with proper redemption handling
CREATE OR REPLACE FUNCTION get_available_balance(p_customer_id uuid)
RETURNS decimal AS $$
DECLARE
  v_available_cashback decimal;
  v_used_redemptions decimal;
  v_final_balance decimal;
BEGIN
  -- Get sum of valid cashback (non-expired approved purchases)
  SELECT COALESCE(SUM(cashback_amount), 0)
  INTO v_available_cashback
  FROM transactions
  WHERE customer_id = p_customer_id
    AND type = 'purchase'
    AND status = 'approved'
    AND expires_at > CURRENT_TIMESTAMP;

  -- Get sum of approved redemptions
  SELECT COALESCE(SUM(amount), 0)
  INTO v_used_redemptions
  FROM transactions
  WHERE customer_id = p_customer_id
    AND type = 'redemption'
    AND status = 'approved';

  -- Calculate final balance
  v_final_balance := GREATEST(v_available_cashback - v_used_redemptions, 0);

  -- Debug logging
  RAISE NOTICE 'Balance calculation for customer %:
    Available cashback: %
    Used redemptions: %
    Final balance: %',
    p_customer_id,
    v_available_cashback,
    v_used_redemptions,
    v_final_balance;

  RETURN v_final_balance;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Update handle_customer_balance trigger
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
    
    -- Get available balance
    SELECT get_available_balance(NEW.customer_id) INTO v_available_balance;

    -- Get expired balance
    SELECT COALESCE(SUM(cashback_amount), 0)
    INTO v_expired_balance
    FROM transactions
    WHERE customer_id = NEW.customer_id
      AND type = 'purchase'
      AND status = 'approved'
      AND expires_at <= CURRENT_TIMESTAMP;

    -- Debug logging
    RAISE NOTICE 'Redemption validation for customer %:
      Requested amount: %
      Available balance: %
      Expired balance: %',
      NEW.customer_id,
      NEW.amount,
      v_available_balance,
      v_expired_balance;

    -- Validate balance
    IF v_available_balance < NEW.amount THEN
      IF v_expired_balance > 0 THEN
        RAISE EXCEPTION 'Você possui R$ % em cashback expirado. Saldo disponível para resgate: R$ %',
          ROUND(v_expired_balance::numeric, 2),
          ROUND(v_available_balance::numeric, 2);
      ELSE
        RAISE EXCEPTION 'Saldo insuficiente para resgate. Disponível: R$ %',
          ROUND(v_available_balance::numeric, 2);
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

-- Drop and recreate trigger
DROP TRIGGER IF EXISTS trg_handle_balance ON transactions;
CREATE TRIGGER trg_handle_balance
  AFTER INSERT OR UPDATE OR DELETE ON transactions
  FOR EACH ROW
  EXECUTE FUNCTION handle_customer_balance();

-- Update all customer balances
UPDATE customers c
SET balance = get_available_balance(c.id),
    updated_at = NOW();