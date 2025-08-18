/*
  # Fix transaction trigger and balance handling

  1. Changes
    - Update handle_customer_balance trigger function to use correct column names
    - Remove references to non-existent saldo_disponivel column
    - Ensure balance calculations use the correct fields

  2. Security
    - No changes to RLS policies
    - Maintains existing security model
*/

-- Drop and recreate the handle_customer_balance function with corrected column references
CREATE OR REPLACE FUNCTION handle_customer_balance()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_customer_balance numeric;
BEGIN
  -- Get current customer balance
  SELECT balance INTO v_customer_balance
  FROM customers
  WHERE id = COALESCE(NEW.customer_id, OLD.customer_id);

  IF TG_OP = 'INSERT' THEN
    IF NEW.type = 'purchase' AND NEW.status = 'approved' THEN
      -- Add cashback to customer balance
      UPDATE customers 
      SET balance = balance + NEW.cashback_amount
      WHERE id = NEW.customer_id;
    ELSIF NEW.type = 'redemption' AND NEW.status = 'approved' THEN
      -- Check if customer has sufficient balance
      IF v_customer_balance < NEW.amount THEN
        RAISE EXCEPTION 'Insufficient balance for redemption';
      END IF;
      -- Deduct redemption amount from balance
      UPDATE customers 
      SET balance = balance - NEW.amount
      WHERE id = NEW.customer_id;
    END IF;
  ELSIF TG_OP = 'UPDATE' THEN
    IF NEW.type = 'purchase' AND NEW.status = 'approved' AND OLD.status != 'approved' THEN
      -- Add cashback when purchase is approved
      UPDATE customers 
      SET balance = balance + NEW.cashback_amount
      WHERE id = NEW.customer_id;
    ELSIF NEW.type = 'redemption' AND NEW.status = 'approved' AND OLD.status != 'approved' THEN
      -- Check if customer has sufficient balance
      IF v_customer_balance < NEW.amount THEN
        RAISE EXCEPTION 'Insufficient balance for redemption';
      END IF;
      -- Deduct redemption amount when approved
      UPDATE customers 
      SET balance = balance - NEW.amount
      WHERE id = NEW.customer_id;
    END IF;
  ELSIF TG_OP = 'DELETE' THEN
    IF OLD.type = 'purchase' AND OLD.status = 'approved' THEN
      -- Remove cashback on purchase deletion
      UPDATE customers 
      SET balance = balance - OLD.cashback_amount
      WHERE id = OLD.customer_id;
    ELSIF OLD.type = 'redemption' AND OLD.status = 'approved' THEN
      -- Restore balance on redemption deletion
      UPDATE customers 
      SET balance = balance + OLD.amount
      WHERE id = OLD.customer_id;
    END IF;
  END IF;

  RETURN COALESCE(NEW, OLD);
END;
$$;

-- Drop and recreate the trigger to ensure it's using the latest version
DROP TRIGGER IF EXISTS trg_handle_balance ON transactions;
CREATE TRIGGER trg_handle_balance
  BEFORE INSERT OR UPDATE OR DELETE ON transactions
  FOR EACH ROW
  EXECUTE FUNCTION handle_customer_balance();