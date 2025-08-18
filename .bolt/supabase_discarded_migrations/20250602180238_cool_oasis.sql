-- Create type for transaction types if it doesn't exist
DO $$ 
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'transaction_type') THEN
    CREATE TYPE transaction_type AS ENUM ('purchase', 'redemption', 'adjustment');
  END IF;
END $$;

-- Add adjustment transactions for negative balances
WITH negative_balances AS (
  SELECT
    c.id as customer_id,
    ABS(
      COALESCE(
        SUM(
          CASE 
            WHEN t.type = 'purchase' AND t.status = 'approved' 
              AND DATE_TRUNC('month', t.created_at) = DATE_TRUNC('month', CURRENT_TIMESTAMP)
            THEN t.cashback_amount
            WHEN t.type = 'redemption' AND t.status = 'approved'
              AND DATE_TRUNC('month', t.created_at) = DATE_TRUNC('month', CURRENT_TIMESTAMP)
            THEN -t.amount
            ELSE 0
          END
        ),
        0
      )
    ) as adjustment_amount
  FROM customers c
  LEFT JOIN transactions t ON t.customer_id = c.id
  GROUP BY c.id
  HAVING COALESCE(
    SUM(
      CASE 
        WHEN t.type = 'purchase' AND t.status = 'approved'
          AND DATE_TRUNC('month', t.created_at) = DATE_TRUNC('month', CURRENT_TIMESTAMP)
        THEN t.cashback_amount
        WHEN t.type = 'redemption' AND t.status = 'approved'
          AND DATE_TRUNC('month', t.created_at) = DATE_TRUNC('month', CURRENT_TIMESTAMP)
        THEN -t.amount
        ELSE 0
      END
    ),
    0
  ) < 0
)
INSERT INTO transactions (
  id,
  customer_id,
  type,
  amount,
  cashback_amount,
  status,
  created_at,
  updated_at,
  comment
)
SELECT
  gen_random_uuid(),
  customer_id,
  'adjustment'::transaction_type,
  adjustment_amount,
  adjustment_amount,
  'approved',
  NOW(),
  NOW(),
  'Ajuste automático de saldo negativo'
FROM negative_balances
WHERE adjustment_amount > 0;

-- Update balance calculation function to handle adjustments
CREATE OR REPLACE FUNCTION get_available_balance(p_customer_id uuid)
RETURNS decimal AS $$
DECLARE
  v_cashback decimal;
  v_redemptions decimal;
  v_adjustments decimal;
BEGIN
  -- Get cashback total for current month
  SELECT COALESCE(SUM(cashback_amount), 0)
  INTO v_cashback
  FROM transactions
  WHERE customer_id = p_customer_id
    AND type = 'purchase'
    AND status = 'approved'
    AND DATE_TRUNC('month', created_at) = DATE_TRUNC('month', CURRENT_TIMESTAMP);

  -- Get redemptions total for current month
  SELECT COALESCE(SUM(amount), 0)
  INTO v_redemptions
  FROM transactions
  WHERE customer_id = p_customer_id
    AND type = 'redemption'
    AND status = 'approved'
    AND DATE_TRUNC('month', created_at) = DATE_TRUNC('month', CURRENT_TIMESTAMP);

  -- Get adjustments total for current month
  SELECT COALESCE(SUM(cashback_amount), 0)
  INTO v_adjustments
  FROM transactions
  WHERE customer_id = p_customer_id
    AND type = 'adjustment'
    AND status = 'approved'
    AND DATE_TRUNC('month', created_at) = DATE_TRUNC('month', CURRENT_TIMESTAMP);

  -- Return available balance (never negative)
  RETURN GREATEST(v_cashback - v_redemptions + v_adjustments, 0);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Update all customer balances
UPDATE customers c
SET balance = get_available_balance(c.id),
    updated_at = NOW();