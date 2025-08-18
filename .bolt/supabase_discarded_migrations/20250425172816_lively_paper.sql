/*
  # Update balance display to show only available balance

  1. Changes
    - Update get_available_balance function to be more explicit
    - Add function to get expired balance
    - Improve error messages
*/

-- Create function to get expired balance
CREATE OR REPLACE FUNCTION get_expired_balance(p_customer_id uuid)
RETURNS decimal AS $$
DECLARE
  v_expired_balance decimal;
BEGIN
  -- Get sum of expired cashback
  SELECT COALESCE(SUM(cashback_amount), 0)
  INTO v_expired_balance
  FROM transactions
  WHERE customer_id = p_customer_id
    AND type = 'purchase'
    AND status = 'approved'
    AND expires_at <= CURRENT_TIMESTAMP;

  RETURN v_expired_balance;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Update get_available_balance function
CREATE OR REPLACE FUNCTION get_available_balance(p_customer_id uuid)
RETURNS decimal AS $$
DECLARE
  v_balance decimal;
  v_redemptions decimal;
BEGIN
  -- Get sum of valid cashback (non-expired approved purchases)
  SELECT COALESCE(SUM(cashback_amount), 0)
  INTO v_balance
  FROM transactions
  WHERE customer_id = p_customer_id
    AND type = 'purchase'
    AND status = 'approved'
    AND expires_at > CURRENT_TIMESTAMP;

  -- Get sum of approved redemptions
  SELECT COALESCE(SUM(amount), 0)
  INTO v_redemptions
  FROM transactions
  WHERE customer_id = p_customer_id
    AND type = 'redemption'
    AND status = 'approved';

  -- Return available balance (never negative)
  RETURN GREATEST(v_balance - v_redemptions, 0);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Update balance handling trigger
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
    
    -- Get available and expired balances
    SELECT get_available_balance(NEW.customer_id) INTO v_available_balance;
    SELECT get_expired_balance(NEW.customer_id) INTO v_expired_balance;

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

  -- Update customer balance to show only available balance
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

-- Add comments
COMMENT ON FUNCTION get_expired_balance IS 'Calculates total expired cashback amount';
COMMENT ON FUNCTION get_available_balance IS 'Calculates available non-expired balance minus redemptions';
COMMENT ON FUNCTION handle_customer_balance IS 'Handles balance updates and validates redemptions with proper error messages';

-- Update all customer balances to show only available balance
UPDATE customers c
SET balance = get_available_balance(c.id),
    updated_at = NOW();