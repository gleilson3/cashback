/*
  # Fix balance calculation and redemption validation

  1. Changes
    - Update get_available_balance function to properly handle expired cashback
    - Improve balance validation in handle_customer_balance trigger
    - Add better error messages in Portuguese

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

-- Create improved balance handling trigger
CREATE OR REPLACE FUNCTION handle_customer_balance()
RETURNS TRIGGER AS $$
DECLARE
  v_available_balance decimal;
BEGIN
  -- For redemptions, verify balance is sufficient
  IF TG_OP IN ('INSERT', 'UPDATE') AND 
     NEW.type = 'redemption' AND 
     NEW.status = 'approved' THEN
    
    -- Get available balance excluding current redemption
    SELECT get_available_balance(NEW.customer_id) INTO v_available_balance;

    -- Validate balance
    IF v_available_balance < NEW.amount THEN
      RAISE EXCEPTION 'Saldo insuficiente para resgate. Disponível: R$ %, Solicitado: R$ %', 
        ROUND(v_available_balance::numeric, 2),
        ROUND(NEW.amount::numeric, 2);
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
COMMENT ON FUNCTION get_available_balance IS 'Calculates available balance considering only non-expired approved purchases minus approved redemptions';
COMMENT ON FUNCTION handle_customer_balance IS 'Handles balance updates and validates redemptions with proper error messages';

-- Update all customer balances
UPDATE customers c
SET balance = get_available_balance(c.id),
    updated_at = NOW();