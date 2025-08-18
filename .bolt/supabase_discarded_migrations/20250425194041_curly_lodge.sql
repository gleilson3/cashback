/*
  # Fix balance validation and error handling

  1. Changes
    - Update balance calculation to handle decimal precision
    - Improve error messages for insufficient balance
    - Add validation for expired cashback
    - Fix rounding issues

  2. Security
    - Maintain existing RLS policies
    - Ensure accurate balance calculations
*/

-- Drop existing trigger first
DROP TRIGGER IF EXISTS trg_handle_balance ON transactions;

-- Drop existing functions
DROP FUNCTION IF EXISTS get_available_balance(uuid);
DROP FUNCTION IF EXISTS handle_customer_balance();

-- Create improved available balance function
CREATE OR REPLACE FUNCTION get_available_balance(p_customer_id uuid)
RETURNS decimal AS $$
DECLARE
  v_available_cashback decimal;
  v_used_redemptions decimal;
  v_final_balance decimal;
BEGIN
  -- Get sum of valid cashback (non-expired approved purchases)
  SELECT COALESCE(SUM(ROUND(cashback_amount::numeric, 2)), 0)
  INTO v_available_cashback
  FROM transactions
  WHERE customer_id = p_customer_id
    AND type = 'purchase'
    AND status = 'approved'
    AND expires_at > CURRENT_TIMESTAMP;

  -- Get sum of approved redemptions
  SELECT COALESCE(SUM(ROUND(amount::numeric, 2)), 0)
  INTO v_used_redemptions
  FROM transactions
  WHERE customer_id = p_customer_id
    AND type = 'redemption'
    AND status = 'approved';

  -- Calculate final balance with proper rounding
  v_final_balance := ROUND((v_available_cashback - v_used_redemptions)::numeric, 2);
  
  -- Debug logging
  RAISE NOTICE 'Balance calculation for customer %:
    Available cashback: %
    Used redemptions: %
    Final balance: %',
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
  v_total_balance decimal;
BEGIN
  -- For redemptions, verify balance is sufficient
  IF TG_OP IN ('INSERT', 'UPDATE') AND 
     NEW.type = 'redemption' AND 
     NEW.status = 'approved' THEN
    
    -- Round the redemption amount
    NEW.amount := ROUND(NEW.amount::numeric, 2);

    -- Get available balance excluding current redemption
    SELECT get_available_balance(NEW.customer_id) INTO v_available_balance;

    -- Get expired balance
    SELECT COALESCE(SUM(ROUND(cashback_amount::numeric, 2)), 0)
    INTO v_expired_balance
    FROM transactions
    WHERE customer_id = NEW.customer_id
      AND type = 'purchase'
      AND status = 'approved'
      AND expires_at <= CURRENT_TIMESTAMP;

    -- Get total balance including expired
    v_total_balance := v_available_balance + v_expired_balance;

    -- Debug logging
    RAISE NOTICE 'Redemption validation for customer %:
      Requested amount: %
      Available balance: %
      Expired balance: %
      Total balance: %',
      NEW.customer_id,
      NEW.amount,
      v_available_balance,
      v_expired_balance,
      v_total_balance;

    -- Validate balance with proper decimal comparison
    IF ROUND(v_available_balance::numeric, 2) < ROUND(NEW.amount::numeric, 2) THEN
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
  SET balance = ROUND(get_available_balance(c.id)::numeric, 2),
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
COMMENT ON FUNCTION get_available_balance IS 'Calculates available balance with proper decimal precision and debug logging';
COMMENT ON FUNCTION handle_customer_balance IS 'Handles balance updates and validates redemptions with improved error handling';

-- Update all customer balances with proper rounding
UPDATE customers c
SET balance = ROUND(get_available_balance(c.id)::numeric, 2),
    updated_at = NOW();