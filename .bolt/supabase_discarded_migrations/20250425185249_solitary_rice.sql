/*
  # Fix balance validation and precision handling

  1. Changes
    - Update balance calculation functions to handle decimal precision
    - Add minimum redemption amount validation
    - Fix rounding issues in balance comparisons
    - Improve error messages

  2. Security
    - Maintain existing RLS policies
    - Ensure accurate balance calculations
*/

-- Drop existing trigger first to avoid dependency issues
DROP TRIGGER IF EXISTS trg_handle_balance ON transactions;

-- Drop existing functions
DROP FUNCTION IF EXISTS get_available_balance(uuid);
DROP FUNCTION IF EXISTS handle_customer_balance();

-- Create improved available balance function with proper decimal handling
CREATE OR REPLACE FUNCTION get_available_balance(p_customer_id uuid)
RETURNS decimal AS $$
DECLARE
  v_available_cashback decimal;
  v_used_redemptions decimal;
  v_final_balance decimal;
BEGIN
  -- Get sum of valid cashback (non-expired approved purchases)
  SELECT COALESCE(SUM(ROUND(cashback_amount, 2)), 0)
  INTO v_available_cashback
  FROM transactions
  WHERE customer_id = p_customer_id
    AND type = 'purchase'
    AND status = 'approved'
    AND expires_at > CURRENT_TIMESTAMP;

  -- Get sum of approved redemptions
  SELECT COALESCE(SUM(ROUND(amount, 2)), 0)
  INTO v_used_redemptions
  FROM transactions
  WHERE customer_id = p_customer_id
    AND type = 'redemption'
    AND status = 'approved';

  -- Calculate final balance with proper rounding
  v_final_balance := ROUND(GREATEST(v_available_cashback - v_used_redemptions, 0), 2);

  RETURN v_final_balance;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create improved balance handling trigger with proper validation
CREATE OR REPLACE FUNCTION handle_customer_balance()
RETURNS TRIGGER AS $$
DECLARE
  v_available_balance decimal;
  v_expired_balance decimal;
  v_min_redemption_amount constant decimal := 1.00; -- Minimum redemption amount
BEGIN
  -- For redemptions, verify balance is sufficient
  IF TG_OP IN ('INSERT', 'UPDATE') AND 
     NEW.type = 'redemption' AND 
     NEW.status = 'approved' THEN
    
    -- Round the redemption amount
    NEW.amount := ROUND(NEW.amount, 2);
    
    -- Validate minimum redemption amount
    IF NEW.amount < v_min_redemption_amount THEN
      RAISE EXCEPTION 'O valor mínimo para resgate é R$ %',
        v_min_redemption_amount;
    END IF;

    -- Get available balance
    SELECT get_available_balance(NEW.customer_id) INTO v_available_balance;

    -- Get expired balance
    SELECT COALESCE(SUM(ROUND(cashback_amount, 2)), 0)
    INTO v_expired_balance
    FROM transactions
    WHERE customer_id = NEW.customer_id
      AND type = 'purchase'
      AND status = 'approved'
      AND expires_at <= CURRENT_TIMESTAMP;

    -- Validate balance with proper decimal comparison
    IF ROUND(v_available_balance, 2) < ROUND(NEW.amount, 2) THEN
      IF v_expired_balance > 0 THEN
        RAISE EXCEPTION 'Você possui R$ % em cashback expirado. Saldo disponível para resgate: R$ %',
          ROUND(v_expired_balance, 2),
          ROUND(v_available_balance, 2);
      ELSE
        RAISE EXCEPTION 'Saldo insuficiente para resgate. Disponível: R$ %',
          ROUND(v_available_balance, 2);
      END IF;
    END IF;
  END IF;

  -- Update customer balance
  UPDATE customers c
  SET balance = ROUND(get_available_balance(c.id), 2),
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
COMMENT ON FUNCTION get_available_balance IS 'Calculates available balance with proper decimal precision';
COMMENT ON FUNCTION handle_customer_balance IS 'Handles balance updates and validates redemptions with proper decimal handling';

-- Update all customer balances with proper rounding
UPDATE customers c
SET balance = ROUND(get_available_balance(c.id), 2),
    updated_at = NOW();