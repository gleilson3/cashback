-- Drop existing trigger first
DROP TRIGGER IF EXISTS trg_handle_balance ON transactions;

-- Drop existing functions
DROP FUNCTION IF EXISTS get_available_balance(uuid);
DROP FUNCTION IF EXISTS handle_customer_balance();

-- Create improved available balance function
CREATE OR REPLACE FUNCTION get_available_balance(p_customer_id uuid)
RETURNS decimal AS $$
DECLARE
  v_customer_record RECORD;
  v_transactions RECORD;
  v_available_cashback decimal := 0;
  v_used_redemptions decimal := 0;
  v_final_balance decimal;
BEGIN
  -- Lock the customer record first
  SELECT * INTO v_customer_record 
  FROM customers 
  WHERE id = p_customer_id 
  FOR UPDATE;

  -- Calculate available cashback from valid transactions
  FOR v_transactions IN 
    SELECT cashback_amount 
    FROM transactions 
    WHERE customer_id = p_customer_id
      AND type = 'purchase'
      AND status = 'approved'
      AND expires_at > CURRENT_TIMESTAMP
  LOOP
    v_available_cashback := v_available_cashback + COALESCE(v_transactions.cashback_amount::numeric, 0);
  END LOOP;

  -- Calculate used redemptions
  FOR v_transactions IN 
    SELECT amount 
    FROM transactions 
    WHERE customer_id = p_customer_id
      AND type = 'redemption'
      AND status = 'approved'
  LOOP
    v_used_redemptions := v_used_redemptions + COALESCE(v_transactions.amount::numeric, 0);
  END LOOP;

  -- Calculate final balance
  v_final_balance := v_available_cashback - v_used_redemptions;
  
  -- Debug logging
  RAISE NOTICE 'Balance calculation for customer %:
    Available cashback: %
    Used redemptions: %
    Final balance: %',
    p_customer_id,
    v_available_cashback,
    v_used_redemptions,
    v_final_balance;
  
  RETURN GREATEST(v_final_balance::decimal, 0);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create improved balance handling function
CREATE OR REPLACE FUNCTION handle_customer_balance()
RETURNS TRIGGER AS $$
DECLARE
  v_customer_record RECORD;
  v_available_balance decimal;
  v_expired_balance decimal := 0;
  v_transactions RECORD;
  v_min_redemption decimal := 1.00; -- Minimum redemption amount
BEGIN
  -- For redemptions, verify balance is sufficient
  IF TG_OP IN ('INSERT', 'UPDATE') AND 
     NEW.type = 'redemption' AND 
     NEW.status = 'approved' THEN

    -- Lock the customer record first
    SELECT * INTO v_customer_record 
    FROM customers 
    WHERE id = NEW.customer_id 
    FOR UPDATE;

    -- Validate minimum redemption amount
    IF NEW.amount < v_min_redemption THEN
      RAISE EXCEPTION 'O valor mínimo para resgate é R$ %', v_min_redemption;
    END IF;
    
    -- Get available balance
    SELECT get_available_balance(NEW.customer_id) INTO v_available_balance;

    -- Calculate expired balance without aggregates
    FOR v_transactions IN 
      SELECT cashback_amount 
      FROM transactions 
      WHERE customer_id = NEW.customer_id
        AND type = 'purchase'
        AND status = 'approved'
        AND expires_at <= CURRENT_TIMESTAMP
    LOOP
      v_expired_balance := v_expired_balance + COALESCE(v_transactions.cashback_amount::numeric, 0);
    END LOOP;

    -- Debug logging
    RAISE NOTICE 'Redemption validation:
      Customer ID: %
      Requested amount: %
      Available balance: %
      Expired balance: %',
      NEW.customer_id,
      NEW.amount,
      v_available_balance,
      v_expired_balance;

    -- Compare values directly
    IF v_available_balance < NEW.amount THEN
      IF v_expired_balance > 0 THEN
        RAISE EXCEPTION 'Você possui R$ % em cashback expirado. Saldo disponível para resgate: R$ %',
          v_expired_balance,
          v_available_balance;
      ELSE
        RAISE EXCEPTION 'Saldo insuficiente para resgate. Disponível: R$ %',
          v_available_balance;
      END IF;
    END IF;
  END IF;

  -- Update customer balance immediately
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
COMMENT ON FUNCTION get_available_balance IS 'Calculates available balance with proper transaction locking';
COMMENT ON FUNCTION handle_customer_balance IS 'Handles balance updates and validates redemptions with synchronous updates';

-- Update all customer balances
UPDATE customers c
SET balance = get_available_balance(c.id),
    updated_at = NOW();