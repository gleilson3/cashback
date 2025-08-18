/*
  # Fix password hashing and verification

  1. Changes
    - Drop and recreate password hashing trigger
    - Update password verification function
    - Ensure proper bcrypt hashing

  2. Security
    - Use bcrypt for password hashing
    - Maintain secure password verification
*/

-- Drop existing triggers and functions
DROP TRIGGER IF EXISTS hash_customer_password_trigger ON customers;
DROP TRIGGER IF EXISTS trg_hash_customer_password ON customers;
DROP FUNCTION IF EXISTS hash_customer_password();
DROP FUNCTION IF EXISTS verify_customer_password(text, text);

-- Create function to hash password
CREATE OR REPLACE FUNCTION hash_customer_password()
RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'INSERT' OR NEW.password_hash != OLD.password_hash THEN
    -- Only hash if the password isn't already hashed (doesn't start with $2a$)
    IF NEW.password_hash IS NOT NULL AND NEW.password_hash != '' AND NEW.password_hash NOT LIKE '$2a$%' THEN
      NEW.password_hash := crypt(NEW.password_hash, gen_salt('bf'));
    END IF;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger for password hashing
CREATE TRIGGER trg_hash_customer_password
  BEFORE INSERT OR UPDATE OF password_hash ON customers
  FOR EACH ROW
  EXECUTE FUNCTION hash_customer_password();

-- Create function to verify password
CREATE OR REPLACE FUNCTION verify_customer_password(
  p_phone text,
  p_password text
)
RETURNS uuid AS $$
DECLARE
  v_customer_id uuid;
  v_password_hash text;
BEGIN
  -- Get customer password hash
  SELECT id, password_hash INTO v_customer_id, v_password_hash
  FROM customers
  WHERE phone = p_phone;

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

-- Add comments
COMMENT ON FUNCTION hash_customer_password() IS 'Automatically hashes customer passwords using bcrypt';
COMMENT ON FUNCTION verify_customer_password(text, text) IS 'Verifies customer password and returns customer ID if valid';