-- Function to validate customer balances
CREATE OR REPLACE FUNCTION validate_customer_balances()
RETURNS TABLE (
  customer_id uuid,
  stored_balance decimal,
  calculated_balance decimal,
  has_mismatch boolean
) AS $$
BEGIN
  RETURN QUERY
  WITH calculated_balances AS (
    SELECT 
      t.customer_id,
      COALESCE(
        SUM(
          CASE 
            WHEN t.type = 'purchase' AND t.status = 'approved' AND t.expires_at > CURRENT_TIMESTAMP 
            THEN t.cashback_amount
            WHEN t.type = 'redemption' AND t.status = 'approved' 
            THEN -t.amount
            ELSE 0
          END
        )::decimal, 
        0
      ) as calc_balance
    FROM transactions t
    GROUP BY t.customer_id
  )
  SELECT 
    c.id as customer_id,
    c.balance as stored_balance,
    cb.calc_balance as calculated_balance,
    (c.balance != cb.calc_balance) as has_mismatch
  FROM customers c
  JOIN calculated_balances cb ON c.id = cb.customer_id
  WHERE c.balance != cb.calc_balance;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to fix customer balances
CREATE OR REPLACE FUNCTION fix_customer_balances()
RETURNS void AS $$
BEGIN
  UPDATE customers c
  SET balance = cb.calc_balance,
      updated_at = NOW()
  FROM (
    SELECT 
      t.customer_id,
      COALESCE(
        SUM(
          CASE 
            WHEN t.type = 'purchase' AND t.status = 'approved' AND t.expires_at > CURRENT_TIMESTAMP 
            THEN t.cashback_amount
            WHEN t.type = 'redemption' AND t.status = 'approved' 
            THEN -t.amount
            ELSE 0
          END
        )::decimal, 
        0
      ) as calc_balance
    FROM transactions t
    GROUP BY t.customer_id
  ) cb
  WHERE c.id = cb.customer_id
  AND c.balance != cb.calc_balance;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to find orphaned transactions
CREATE OR REPLACE FUNCTION find_orphaned_transactions()
RETURNS TABLE (
  transaction_id uuid,
  customer_id uuid,
  type text,
  status text,
  created_at timestamptz
) AS $$
BEGIN
  RETURN QUERY
  SELECT 
    t.id,
    t.customer_id,
    t.type,
    t.status,
    t.created_at
  FROM transactions t
  LEFT JOIN customers c ON t.customer_id = c.id
  WHERE c.id IS NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to validate transaction expiration dates
CREATE OR REPLACE FUNCTION validate_transaction_expiration()
RETURNS TABLE (
  transaction_id uuid,
  customer_id uuid,
  created_at timestamptz,
  expires_at timestamptz,
  issue_type text
) AS $$
BEGIN
  RETURN QUERY
  SELECT 
    t.id,
    t.customer_id,
    t.created_at,
    t.expires_at,
    CASE
      WHEN t.expires_at IS NULL AND t.type = 'purchase' THEN 'missing_expiration'
      WHEN t.expires_at <= t.created_at THEN 'invalid_expiration'
      ELSE 'other'
    END as issue_type
  FROM transactions t
  WHERE 
    (t.type = 'purchase' AND t.expires_at IS NULL)
    OR (t.expires_at <= t.created_at);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to fix transaction expiration dates
CREATE OR REPLACE FUNCTION fix_transaction_expiration()
RETURNS void AS $$
BEGIN
  -- Fix missing expiration dates
  UPDATE transactions
  SET expires_at = date_trunc('month', created_at) + interval '1 month' - interval '1 second'
  WHERE type = 'purchase' AND expires_at IS NULL;

  -- Fix invalid expiration dates
  UPDATE transactions
  SET expires_at = date_trunc('month', created_at) + interval '1 month' - interval '1 second'
  WHERE expires_at <= created_at;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Add missing indexes
CREATE INDEX IF NOT EXISTS idx_transactions_customer_type_status 
ON transactions (customer_id, type, status);

CREATE INDEX IF NOT EXISTS idx_transactions_created_at 
ON transactions (created_at);

-- Fix any existing data issues
DO $$ 
BEGIN
  -- Fix transaction expiration dates
  PERFORM fix_transaction_expiration();
  
  -- Fix customer balances
  PERFORM fix_customer_balances();
  
  -- Log completion
  RAISE NOTICE 'Database consistency checks and fixes completed';
END $$;