-- Create function to calculate cashback amount
CREATE OR REPLACE FUNCTION calculate_purchase_cashback()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.type = 'purchase' AND NEW.status = 'approved' THEN
    -- Calculate 5% cashback
    NEW.cashback_amount = ROUND((NEW.amount * 0.05)::numeric, 2);
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Drop existing trigger if it exists and create new one
DROP TRIGGER IF EXISTS trg_calculate_purchase_cashback ON transactions;
CREATE TRIGGER trg_calculate_purchase_cashback
  BEFORE INSERT OR UPDATE ON transactions
  FOR EACH ROW
  EXECUTE FUNCTION calculate_purchase_cashback();

-- Add comment to function
COMMENT ON FUNCTION calculate_purchase_cashback IS 'Automatically calculates cashback for purchases';

-- Generate missing cashback for existing purchases
UPDATE transactions
SET 
  cashback_amount = ROUND((amount * 0.05)::numeric, 2),
  updated_at = NOW(),
  comment = CASE 
    WHEN comment IS NULL THEN 'Cashback calculado automaticamente'
    ELSE comment || ' | Cashback calculado automaticamente'
  END
WHERE type = 'purchase'
  AND status = 'approved'
  AND (cashback_amount IS NULL OR cashback_amount = 0);

-- Update balance calculation function
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

-- Drop existing trigger if it exists and create new one
DROP TRIGGER IF EXISTS trg_handle_balance ON transactions;
CREATE TRIGGER trg_handle_balance
  BEFORE INSERT OR UPDATE OR DELETE ON transactions
  FOR EACH ROW
  EXECUTE FUNCTION handle_customer_balance();

-- Add comments
COMMENT ON FUNCTION get_available_balance IS 'Calculates available balance including cashback and adjustments';
COMMENT ON FUNCTION handle_customer_balance IS 'Handles balance updates and creates adjustments when needed';

-- Update all customer balances
UPDATE customers c
SET balance = get_available_balance(c.id),
    updated_at = NOW();