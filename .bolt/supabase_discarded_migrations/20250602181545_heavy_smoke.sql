/*
  # Generate missing cashback transactions

  1. Changes
    - Add function to calculate cashback amount
    - Create missing cashback transactions for purchases
    - Update balance calculation to include cashback
    - Fix any inconsistencies in existing data

  2. Security
    - Maintain existing RLS policies
    - Ensure data integrity
*/

-- Create function to calculate cashback amount
CREATE OR REPLACE FUNCTION calculate_cashback_amount(purchase_amount decimal)
RETURNS decimal AS $$
BEGIN
  -- 5% cashback rate
  RETURN ROUND((purchase_amount * 0.05)::numeric, 2);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Generate missing cashback for purchases
WITH missing_cashback AS (
  SELECT 
    t.id as purchase_id,
    t.customer_id,
    t.amount as purchase_amount,
    t.created_at as purchase_date,
    calculate_cashback_amount(t.amount) as cashback_amount
  FROM transactions t
  WHERE t.type = 'purchase'
    AND t.status = 'approved'
    -- Only consider purchases that don't have cashback set
    AND (t.cashback_amount IS NULL OR t.cashback_amount = 0)
)
UPDATE transactions t
SET 
  cashback_amount = mc.cashback_amount,
  updated_at = NOW(),
  comment = CASE 
    WHEN t.comment IS NULL THEN 'Cashback calculado automaticamente'
    ELSE t.comment || ' | Cashback calculado automaticamente'
  END
FROM missing_cashback mc
WHERE t.id = mc.purchase_id;

-- Update balance calculation function to properly handle cashback
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

-- Create trigger to automatically calculate cashback for new purchases
CREATE OR REPLACE FUNCTION calculate_purchase_cashback()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.type = 'purchase' AND NEW.status = 'approved' THEN
    NEW.cashback_amount = calculate_cashback_amount(NEW.amount);
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger
CREATE TRIGGER trg_calculate_purchase_cashback
  BEFORE INSERT OR UPDATE ON transactions
  FOR EACH ROW
  EXECUTE FUNCTION calculate_purchase_cashback();

-- Add comments
COMMENT ON FUNCTION calculate_cashback_amount IS 'Calculates cashback amount based on purchase amount';
COMMENT ON FUNCTION calculate_purchase_cashback IS 'Automatically calculates cashback for new purchases';

-- Update all customer balances
UPDATE customers c
SET balance = get_available_balance(c.id),
    updated_at = NOW();