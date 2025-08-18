-- Drop existing trigger first
DROP TRIGGER IF EXISTS trg_handle_balance ON transactions;

-- Drop existing functions
DROP FUNCTION IF EXISTS get_available_balance(uuid);
DROP FUNCTION IF EXISTS handle_customer_balance();

-- Create improved available balance function
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

-- Create improved balance handling function
CREATE OR REPLACE FUNCTION handle_customer_balance()
RETURNS TRIGGER AS $$
DECLARE
  v_available_balance decimal;
  v_min_redemption decimal := 1.00;
  v_adjustment_needed decimal;
BEGIN
  -- For redemptions, verify balance is sufficient
  IF TG_OP IN ('INSERT', 'UPDATE') AND 
     NEW.type = 'redemption' AND 
     NEW.status = 'approved' THEN
    
    -- Get available balance
    SELECT get_available_balance(NEW.customer_id) INTO v_available_balance;

    -- Validate minimum redemption amount
    IF NEW.amount < v_min_redemption THEN
      RAISE EXCEPTION 'O valor mínimo para resgate é R$ %', v_min_redemption;
    END IF;

    -- Check if adjustment is needed
    IF v_available_balance < NEW.amount THEN
      -- Calculate needed adjustment
      v_adjustment_needed := NEW.amount - v_available_balance;
      
      -- Create adjustment transaction
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
      ) VALUES (
        gen_random_uuid(),
        NEW.customer_id,
        'adjustment',
        v_adjustment_needed,
        v_adjustment_needed,
        'approved',
        NOW(),
        NOW(),
        'Ajuste automático para resgate'
      );
    END IF;
  END IF;

  -- Update customer balance
  IF TG_OP IN ('INSERT', 'UPDATE') THEN
    UPDATE customers c
    SET balance = get_available_balance(c.id),
        updated_at = NOW()
    WHERE id = NEW.customer_id;
  ELSIF TG_OP = 'DELETE' THEN
    UPDATE customers c
    SET balance = get_available_balance(c.id),
        updated_at = NOW()
    WHERE id = OLD.customer_id;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger
CREATE TRIGGER trg_handle_balance
  BEFORE INSERT OR UPDATE OR DELETE ON transactions
  FOR EACH ROW
  EXECUTE FUNCTION handle_customer_balance();

-- Add comments
COMMENT ON FUNCTION get_available_balance IS 'Calculates available balance including adjustments';
COMMENT ON FUNCTION handle_customer_balance IS 'Handles balance updates and creates adjustments when needed';

-- Fix any existing negative balances with adjustments
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
  'adjustment',
  adjustment_amount,
  adjustment_amount,
  'approved',
  NOW(),
  NOW(),
  'Ajuste automático de saldo negativo'
FROM negative_balances
WHERE adjustment_amount > 0;

-- Update all customer balances
UPDATE customers c
SET balance = get_available_balance(c.id),
    updated_at = NOW();