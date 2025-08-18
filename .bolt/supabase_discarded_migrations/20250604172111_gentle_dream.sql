-- Drop existing triggers and views first
DROP TRIGGER IF EXISTS trg_handle_balance ON transactions;
DROP VIEW IF EXISTS customer_balances;

-- Create view for customer balances with proper monthly handling
CREATE OR REPLACE VIEW customer_balances AS
WITH monthly_transactions AS (
  SELECT 
    customer_id,
    SUM(
      CASE 
        WHEN type = 'purchase' AND status = 'approved' THEN cashback_amount
        WHEN type = 'redemption' AND status = 'approved' THEN -amount
        WHEN type = 'adjustment' AND status = 'approved' THEN cashback_amount
        ELSE 0
      END
    ) as month_balance
  FROM transactions
  WHERE DATE_TRUNC('month', created_at) = DATE_TRUNC('month', CURRENT_TIMESTAMP)
  GROUP BY customer_id
),
next_expiring AS (
  SELECT DISTINCT ON (customer_id)
    customer_id,
    cashback_amount as expiring_amount,
    expires_at as expiration_date
  FROM transactions
  WHERE type = 'purchase'
    AND status = 'approved'
    AND expires_at > CURRENT_TIMESTAMP
  ORDER BY customer_id, expires_at ASC
)
SELECT 
  c.id as customer_id,
  c.name,
  GREATEST(COALESCE(mt.month_balance, 0), 0) as available_balance,
  ne.expiring_amount,
  ne.expiration_date
FROM customers c
LEFT JOIN monthly_transactions mt ON c.id = mt.customer_id
LEFT JOIN next_expiring ne ON c.id = ne.customer_id;

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
      RAISE EXCEPTION 'Insufficient balance for redemption. Available: %, Requested: %',
        COALESCE(v_available_balance, 0),
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

-- Add comments
COMMENT ON VIEW customer_balances IS 'Shows customer balances with proper monthly handling';
COMMENT ON FUNCTION validate_redemption IS 'Validates redemption transactions against available balance';