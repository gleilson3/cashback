-- Drop the existing view if it exists
DROP VIEW IF EXISTS customer_balances;

-- Create the updated view with correct columns
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

-- Add comment
COMMENT ON VIEW customer_balances IS 'Shows customer balances with proper expiration handling';