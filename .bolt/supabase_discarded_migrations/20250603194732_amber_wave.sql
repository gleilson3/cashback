-- Drop existing view if it exists
DROP VIEW IF EXISTS customer_balances;

-- Create view for customer balances
CREATE VIEW customer_balances AS
SELECT 
  c.id as customer_id,
  c.name,
  GREATEST(
    COALESCE(
      (
        SELECT SUM(
          CASE 
            WHEN type = 'purchase' AND status = 'approved' THEN cashback_amount
            WHEN type = 'redemption' AND status = 'approved' THEN -amount
            WHEN type = 'adjustment' AND status = 'approved' THEN cashback_amount
            ELSE 0
          END
        )
        FROM transactions t
        WHERE t.customer_id = c.id
        AND DATE_TRUNC('month', t.created_at) = DATE_TRUNC('month', CURRENT_TIMESTAMP)
      ),
      0
    ),
    0
  ) as amount,
  (
    SELECT cashback_amount
    FROM transactions t
    WHERE t.customer_id = c.id
      AND t.type = 'purchase'
      AND t.status = 'approved'
      AND t.expires_at > CURRENT_TIMESTAMP
    ORDER BY t.expires_at ASC
    LIMIT 1
  ) as proximo_cashback_expirando,
  (
    SELECT expires_at
    FROM transactions t
    WHERE t.customer_id = c.id
      AND t.type = 'purchase'
      AND t.status = 'approved'
      AND t.expires_at > CURRENT_TIMESTAMP
    ORDER BY t.expires_at ASC
    LIMIT 1
  ) as data_expiracao
FROM customers c;

-- Add comment
COMMENT ON VIEW customer_balances IS 'Shows customer balances with strict non-negative balance handling';