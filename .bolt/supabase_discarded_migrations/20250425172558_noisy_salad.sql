/*
  # Fix balance calculation and display

  1. Changes
    - Update get_available_balance function to properly handle expired cashback
    - Add function to get total balance (including expired)
    - Update balance display logic
    - Improve error messages

  2. Security
    - Maintain existing RLS policies
    - Ensure accurate balance calculations
*/

-- Drop existing functions
DROP FUNCTION IF EXISTS get_available_balance(uuid);
DROP FUNCTION IF EXISTS get_total_balance(uuid);

-- Create function to get total balance (including expired)
CREATE OR REPLACE FUNCTION get_total_balance(p_customer_id uuid)
RETURNS decimal AS $$
DECLARE
  v_balance decimal;
  v_redemptions decimal;
BEGIN
  -- Get sum of all approved purchases
  SELECT COALESCE(SUM(cashback_amount), 0)
  INTO v_balance
  FROM transactions
  WHERE customer_id = p_customer_id
    AND type = 'purchase'
    AND status = 'approved';

  -- Get sum of approved redemptions
  SELECT COALESCE(SUM(amount), 0)
  INTO v_redemptions
  FROM transactions
  WHERE customer_id = p_customer_id
    AND type = 'redemption'
    AND status = 'approved';

  -- Return total balance (never negative)
  RETURN GREATEST(v_balance - v_redemptions, 0);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create function to get available balance (non-expired only)
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
  v_total_balance decimal;
BEGIN
  -- For redemptions, verify balance is sufficient
  IF TG_OP IN ('INSERT', 'UPDATE') AND 
     NEW.type = 'redemption' AND 
     NEW.status = 'approved' THEN
    
    -- Get available balance excluding current redemption
    SELECT get_available_balance(NEW.customer_id) INTO v_available_balance;
    SELECT get_total_balance(NEW.customer_id) INTO v_total_balance;

    -- Validate balance
    IF v_available_balance < NEW.amount THEN
      IF v_total_balance >= NEW.amount THEN
        RAISE EXCEPTION 'Parte do seu saldo está expirado. Saldo disponível: R$ %, Saldo total: R$ %, Solicitado: R$ %',
          ROUND(v_available_balance::numeric, 2),
          ROUND(v_total_balance::numeric, 2),
          ROUND(NEW.amount::numeric, 2);
      ELSE
        RAISE EXCEPTION 'Saldo insuficiente para resgate. Disponível: R$ %, Solicitado: R$ %',
          ROUND(v_available_balance::numeric, 2),
          ROUND(NEW.amount::numeric, 2);
      END IF;
    END IF;
  END IF;

  -- Update customer balance
  UPDATE customers c
  SET balance = get_total_balance(c.id),
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
COMMENT ON FUNCTION get_total_balance IS 'Calculates total balance including expired cashback';
COMMENT ON FUNCTION get_available_balance IS 'Calculates available balance considering only non-expired approved purchases';
COMMENT ON FUNCTION handle_customer_balance IS 'Handles balance updates and validates redemptions with proper error messages';

-- Update all customer balances
UPDATE customers c
SET balance = get_total_balance(c.id),
    updated_at = NOW();