/*
  # Fix balance calculation and add validation function

  1. Changes
    - Add function to get available balance
    - Improve balance calculation accuracy
    - Add better validation for redemptions

  2. Security
    - Maintain existing RLS policies
    - Ensure accurate balance tracking
*/

-- Create function to get available balance
CREATE OR REPLACE FUNCTION get_available_balance(p_customer_id uuid)
RETURNS decimal AS $$
DECLARE
  v_balance decimal;
BEGIN
  SELECT COALESCE(
    (
      SELECT SUM(cashback_amount)
      FROM transactions
      WHERE customer_id = p_customer_id
      AND type = 'purchase'
      AND status = 'approved'
      AND (expires_at IS NULL OR expires_at > now())
    ) -
    COALESCE(
      (
        SELECT SUM(amount)
        FROM transactions
        WHERE customer_id = p_customer_id
        AND type = 'redemption'
        AND status = 'approved'
      ), 0
    ),
    0
  ) INTO v_balance;

  RETURN v_balance;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Update balance handling trigger
CREATE OR REPLACE FUNCTION handle_customer_balance()
RETURNS TRIGGER AS $$
DECLARE
  v_available_balance decimal;
BEGIN
  -- For redemptions, verify balance is sufficient
  IF TG_OP IN ('INSERT', 'UPDATE') AND 
     NEW.type = 'redemption' AND 
     NEW.status = 'approved' THEN
    
    -- Get available balance
    SELECT get_available_balance(NEW.customer_id) INTO v_available_balance;

    IF v_available_balance < NEW.amount THEN
      RAISE EXCEPTION 'Insufficient balance for redemption. Available: %, Requested: %', 
        v_available_balance, NEW.amount;
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

-- Ensure trigger is properly set
DROP TRIGGER IF EXISTS trg_handle_balance ON transactions;
CREATE TRIGGER trg_handle_balance
  AFTER INSERT OR UPDATE OR DELETE ON transactions
  FOR EACH ROW
  EXECUTE FUNCTION handle_customer_balance();

-- Add comments
COMMENT ON FUNCTION get_available_balance IS 'Calculates available balance for a customer considering expiration dates';
COMMENT ON FUNCTION handle_customer_balance IS 'Handles balance updates and validates redemptions';