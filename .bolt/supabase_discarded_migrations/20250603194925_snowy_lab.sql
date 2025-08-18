/*
  # Update customer_balances view

  1. Changes
    - Drop and recreate customer_balances view with correct columns
    - Add available_balance calculation
    - Add expiring_amount and expiration_date calculations
    - Ensure non-negative balances
    - Handle expired cashback

  2. Security
    - View inherits RLS from underlying tables
*/

-- Drop the existing view if it exists
DROP VIEW IF EXISTS customer_balances;

-- Create the updated view with correct columns
CREATE OR REPLACE VIEW customer_balances AS
WITH cashback_transactions AS (
  SELECT 
    customer_id,
    COALESCE(SUM(
      CASE 
        WHEN type = 'purchase' 
          AND status = 'approved' 
          AND (expires_at IS NULL OR expires_at > NOW())
        THEN cashback_amount
        WHEN type = 'redemption' 
          AND status = 'approved'
        THEN cashback_amount
        ELSE 0
      END
    ), 0) as available_balance,
    (
      SELECT cashback_amount
      FROM transactions t2
      WHERE t2.customer_id = t1.customer_id
        AND t2.type = 'purchase'
        AND t2.status = 'approved'
        AND t2.expires_at > NOW()
      ORDER BY t2.expires_at ASC
      LIMIT 1
    ) as expiring_amount,
    (
      SELECT expires_at
      FROM transactions t2
      WHERE t2.customer_id = t1.customer_id
        AND t2.type = 'purchase'
        AND t2.status = 'approved'
        AND t2.expires_at > NOW()
      ORDER BY t2.expires_at ASC
      LIMIT 1
    ) as expiration_date
  FROM transactions t1
  GROUP BY customer_id
)
SELECT 
  c.id as customer_id,
  c.name,
  GREATEST(COALESCE(ct.available_balance, 0), 0) as available_balance,
  GREATEST(COALESCE(ct.expiring_amount, 0), 0) as expiring_amount,
  ct.expiration_date
FROM customers c
LEFT JOIN cashback_transactions ct ON c.id = ct.customer_id;