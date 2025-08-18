-- Drop existing triggers and functions first
DROP TRIGGER IF EXISTS trg_validate_redemption ON transactions;
DROP TRIGGER IF EXISTS trg_handle_balance ON transactions;
DROP FUNCTION IF EXISTS validate_redemption();
DROP FUNCTION IF EXISTS handle_customer_balance();

-- Create function to validate redemption
CREATE OR REPLACE FUNCTION validate_redemption()
RETURNS TRIGGER AS $$
DECLARE
  v_available_balance numeric;
BEGIN
  -- Only validate approved redemptions
  IF NEW.type = 'redemption' AND NEW.status = 'approved' THEN
    -- Get available balance from view
    SELECT available_balance INTO v_available_balance
    FROM customer_balances
    WHERE customer_id = NEW.customer_id;

    -- Check if balance is sufficient
    IF COALESCE(v_available_balance, 0) < NEW.amount THEN
      RAISE EXCEPTION 'Saldo insuficiente para resgate. Disponível: R$ %, Solicitado: R$ %',
        ROUND(COALESCE(v_available_balance, 0)::numeric, 2),
        ROUND(NEW.amount::numeric, 2);
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
    UPDATE customers c
    SET balance = (
      SELECT available_balance 
      FROM customer_balances 
      WHERE customer_id = NEW.customer_id
    ),
    updated_at = NOW()
    WHERE id = NEW.customer_id;
  ELSIF TG_OP = 'DELETE' THEN
    UPDATE customers c
    SET balance = (
      SELECT available_balance 
      FROM customer_balances 
      WHERE customer_id = OLD.customer_id
    ),
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
COMMENT ON FUNCTION validate_redemption IS 'Validates redemption transactions against available balance';
COMMENT ON FUNCTION handle_customer_balance IS 'Updates customer balance after transaction changes';

-- Update all customer balances
UPDATE customers c
SET balance = (
  SELECT available_balance 
  FROM customer_balances 
  WHERE customer_id = c.id
),
updated_at = NOW();