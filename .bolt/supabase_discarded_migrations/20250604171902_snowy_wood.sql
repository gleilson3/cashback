/*
  # Fix trigger column name

  1. Changes
    - Update handle_customer_balance function to use correct column names
    - Drop and recreate trigger with fixed column references
    
  2. Security
    - No changes to RLS policies
    - No changes to table permissions
*/

-- First drop the existing trigger
DROP TRIGGER IF EXISTS trg_handle_balance ON transactions;

-- Then recreate the function with correct column names
CREATE OR REPLACE FUNCTION handle_customer_balance()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_customer_balance numeric;
BEGIN
  -- For new transactions
  IF TG_OP = 'INSERT' THEN
    -- If it's a purchase that's approved, add the cashback to balance
    IF NEW.type = 'purchase' AND NEW.status = 'approved' THEN
      UPDATE customers 
      SET balance = balance + NEW.cashback_amount
      WHERE id = NEW.customer_id;
      
    -- If it's a redemption that's approved, check and subtract from balance
    ELSIF NEW.type = 'redemption' AND NEW.status = 'approved' THEN
      -- Get current balance
      SELECT balance INTO v_customer_balance
      FROM customers
      WHERE id = NEW.customer_id;
      
      -- Verify sufficient balance
      IF v_customer_balance < NEW.amount THEN
        RAISE EXCEPTION 'Insufficient balance for redemption';
      END IF;
      
      -- Update balance
      UPDATE customers
      SET balance = balance - NEW.amount
      WHERE id = NEW.customer_id;
    END IF;
    
    RETURN NEW;
  END IF;
  
  -- For updates to existing transactions
  IF TG_OP = 'UPDATE' THEN
    -- If status changed to approved for a purchase
    IF NEW.type = 'purchase' AND NEW.status = 'approved' AND OLD.status != 'approved' THEN
      UPDATE customers
      SET balance = balance + NEW.cashback_amount
      WHERE id = NEW.customer_id;
      
    -- If status changed to approved for a redemption
    ELSIF NEW.type = 'redemption' AND NEW.status = 'approved' AND OLD.status != 'approved' THEN
      -- Get current balance
      SELECT balance INTO v_customer_balance
      FROM customers
      WHERE id = NEW.customer_id;
      
      -- Verify sufficient balance
      IF v_customer_balance < NEW.amount THEN
        RAISE EXCEPTION 'Insufficient balance for redemption';
      END IF;
      
      -- Update balance
      UPDATE customers
      SET balance = balance - NEW.amount
      WHERE id = NEW.customer_id;
      
    -- If status changed from approved for a purchase
    ELSIF NEW.type = 'purchase' AND OLD.status = 'approved' AND NEW.status != 'approved' THEN
      UPDATE customers
      SET balance = balance - OLD.cashback_amount
      WHERE id = NEW.customer_id;
      
    -- If status changed from approved for a redemption
    ELSIF NEW.type = 'redemption' AND OLD.status = 'approved' AND NEW.status != 'approved' THEN
      UPDATE customers
      SET balance = balance + OLD.amount
      WHERE id = NEW.customer_id;
    END IF;
    
    RETURN NEW;
  END IF;
  
  -- For deleted transactions
  IF TG_OP = 'DELETE' THEN
    -- If deleting an approved purchase
    IF OLD.type = 'purchase' AND OLD.status = 'approved' THEN
      UPDATE customers
      SET balance = balance - OLD.cashback_amount
      WHERE id = OLD.customer_id;
      
    -- If deleting an approved redemption
    ELSIF OLD.type = 'redemption' AND OLD.status = 'approved' THEN
      UPDATE customers
      SET balance = balance + OLD.amount
      WHERE id = OLD.customer_id;
    END IF;
    
    RETURN OLD;
  END IF;
  
  RETURN NULL;
END;
$$;

-- Recreate the trigger
CREATE TRIGGER trg_handle_balance
  BEFORE INSERT OR UPDATE OR DELETE ON transactions
  FOR EACH ROW
  EXECUTE FUNCTION handle_customer_balance();