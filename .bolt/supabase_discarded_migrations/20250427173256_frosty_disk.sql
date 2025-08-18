-- Drop existing function
DROP FUNCTION IF EXISTS verify_customer_password(text, text);

-- Create updated function to use email instead of phone
CREATE OR REPLACE FUNCTION verify_customer_password(
  p_email text,
  p_password text
)
RETURNS uuid AS $$
DECLARE
  v_customer_id uuid;
  v_password_hash text;
BEGIN
  -- Get customer password hash
  SELECT id, password_hash 
  INTO v_customer_id, v_password_hash
  FROM customers
  WHERE email = p_email;

  -- Check if customer exists and verify password
  IF v_customer_id IS NOT NULL AND 
     v_password_hash = crypt(p_password, v_password_hash) THEN
    -- Update last login timestamp
    UPDATE customers
    SET last_login = now()
    WHERE id = v_customer_id;
    
    RETURN v_customer_id;
  END IF;

  RETURN NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Add comment
COMMENT ON FUNCTION verify_customer_password IS 'Verifies customer password using email and returns customer ID if valid';