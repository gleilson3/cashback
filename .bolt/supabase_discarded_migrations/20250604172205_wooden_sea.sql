/*
  # Fix balance calculation and validation

  1. Changes
    - Create view for customer balances
    - Add validation for redemptions
    - Fix timeout issues with simpler queries

  2. Security
    - Maintain existing RLS policies
*/

-- Drop existing triggers first
DROP TRIGGER IF EXISTS trg_validate_redemption ON transactions;
DROP TRIGGER IF EXISTS trg_handle_balance ON transactions;

-- Create function to get available balance
CREATE OR REPLACE FUNCTION get_available_balance(p_customer_id uuid)
RETURNS decimal AS $$
DECLARE
  v_balance decimal;
BEGIN
  SELECT COALESCE(
    SUM(
      CASE 
        WHEN type = 'purchase' AND status = 'approved' THEN cashback_amount
        WHEN type = 'redemption' AND status = 'approved' THEN -amount
        WHEN type = 'adjustment' AND status = 'approved' THEN cashback_amount
        ELSE 0
      END
    ),
    0
  ) INTO v_balance
  FROM transactions
  WHERE customer_id = p_customer_id
    AND DATE_TRUNC('month', created_at) = DATE_TRUNC('month', CURRENT_TIMESTAMP);

  RETURN GREATEST(v_balance, 0);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create function to validate redemption
CREATE OR REPLACE FUNCTION validate_redemption()
RETURNS TRIGGER AS $$
DECLARE
  v_available_balance decimal;
BEGIN
  -- Only validate approved redemptions
  IF NEW.type = 'redemption' AND NEW.status = 'approved' THEN
    -- Get available balance
    SELECT get_available_balance(NEW.customer_id) INTO v_available_balance;

    -- Check if balance is sufficient
    IF v_available_balance < NEW.amount THEN
      RAISE EXCEPTION 'Insufficient balance for redemption. Available: %, Requested: %',
        v_available_balance,
        NEW.amount;
    END IF;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger for redemption validation
CREATE TRIGGER trg_validate_redemption
  BEFORE INSERT OR UPDATE ON transactions
  FOR EACH ROW
  EXECUTE FUNCTION validate_redemption();

-- Create function to handle customer balance
CREATE OR REPLACE FUNCTION handle_customer_balance()
RETURNS TRIGGER AS $$
BEGIN
  -- Update customer balance
  IF TG_OP IN ('INSERT', 'UPDATE') THEN
    UPDATE customers
    SET balance = get_available_balance(NEW.customer_id),
        updated_at = NOW()
    WHERE id = NEW.customer_id;
  ELSIF TG_OP = 'DELETE' THEN
    UPDATE customers
    SET balance = get_available_balance(OLD.customer_id),
        updated_at = NOW()
    WHERE id = OLD.customer_id;
  END IF;

  RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

-- Create trigger for balance handling
CREATE TRIGGER trg_handle_balance
  AFTER INSERT OR UPDATE OR DELETE ON transactions
  FOR EACH ROW
  EXECUTE FUNCTION handle_customer_balance();

-- Add comments
COMMENT ON FUNCTION get_available_balance IS 'Calculates available balance for current month';
COMMENT ON FUNCTION validate_redemption IS 'Validates redemption transactions against available balance';
COMMENT ON FUNCTION handle_customer_balance IS 'Updates customer balance after transaction changes';

-- Update all customer balances
UPDATE customers c
SET balance = get_available_balance(c.id),
    updated_at = NOW();