-- Drop existing trigger first
DROP TRIGGER IF EXISTS trg_handle_balance ON transactions;

-- Drop existing functions
DROP FUNCTION IF EXISTS get_available_balance(uuid);
DROP FUNCTION IF EXISTS handle_customer_balance();

-- Create improved available balance function
CREATE OR REPLACE FUNCTION get_available_balance(p_customer_id uuid)
RETURNS decimal AS $$
DECLARE
  v_balance decimal;
BEGIN
  -- Calculate available balance from non-expired approved purchases
  SELECT COALESCE(
    (
      SELECT SUM(cashback_amount)
      FROM transactions
      WHERE customer_id = p_customer_id
      AND type = 'purchase'
      AND status = 'approved'
      AND expires_at > CURRENT_TIMESTAMP
    ), 0
  ) -
  -- Subtract approved redemptions
  COALESCE(
    (
      SELECT SUM(amount)
      FROM transactions
      WHERE customer_id = p_customer_id
      AND type = 'redemption'
      AND status = 'approved'
    ), 0
  ) INTO v_balance;

  RETURN GREATEST(v_balance, 0); -- Ensure we never return negative balance
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create improved balance handling trigger
CREATE OR REPLACE FUNCTION handle_customer_balance()
RETURNS TRIGGER AS $$
DECLARE
  v_available_balance decimal;
BEGIN
  -- For redemptions, verify balance is sufficient
  IF TG_OP IN ('INSERT', 'UPDATE') AND 
     NEW.type = 'redemption' AND 
     NEW.status = 'approved' THEN
    
    -- Get available balance excluding current redemption
    SELECT get_available_balance(NEW.customer_id) INTO v_available_balance;

    IF v_available_balance < NEW.amount THEN
      RAISE EXCEPTION 'Saldo insuficiente para resgate. Disponível: R$ %, Solicitado: R$ %', 
        v_available_balance, NEW.amount;
    END IF;
  END IF;

  -- Update customer balance
  UPDATE customers c
  SET balance = get_available_balance(c.id),
      updated_at = NOW()
  WHERE id = COALESCE(NEW.customer_id, OLD.customer_id);

  RETURN CASE TG_OP
    WHEN 'DELETE' THEN OLD
    ELSE NEW
  END;
END;
$$ LANGUAGE plpgsql;

-- Create trigger
CREATE TRIGGER trg_handle_balance
  AFTER INSERT OR UPDATE OR DELETE ON transactions
  FOR EACH ROW
  EXECUTE FUNCTION handle_customer_balance();

-- Add comments
COMMENT ON FUNCTION get_available_balance IS 'Calculates available balance considering only non-expired approved purchases minus approved redemptions';
COMMENT ON FUNCTION handle_customer_balance IS 'Handles balance updates and validates redemptions with proper error messages';

-- Update existing balances
UPDATE customers c
SET balance = get_available_balance(c.id),
    updated_at = NOW();