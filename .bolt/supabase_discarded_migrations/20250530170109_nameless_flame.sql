/*
  # Update customer password handling

  1. Changes
    - Creates a new function to properly hash passwords using bcrypt
    - Updates the customer registration process to use hashed passwords
    - Adds a function to verify customer passwords

  2. Security
    - Implements secure password hashing
    - Adds proper password verification
*/

-- Create or replace the password hashing function
CREATE OR REPLACE FUNCTION hash_customer_password()
RETURNS trigger AS $$
BEGIN
  IF TG_OP = 'INSERT' OR NEW.password_hash <> OLD.password_hash THEN
    NEW.password_hash := crypt(NEW.password_hash, gen_salt('bf'));
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create or replace the password verification function
CREATE OR REPLACE FUNCTION verify_customer_password(p_email TEXT, p_password TEXT)
RETURNS UUID AS $$
DECLARE
  v_customer_id UUID;
  v_password_hash TEXT;
BEGIN
  -- Get the customer's ID and hashed password
  SELECT id, password_hash INTO v_customer_id, v_password_hash
  FROM customers
  WHERE email = p_email;

  -- If customer found and password matches
  IF v_customer_id IS NOT NULL AND v_password_hash = crypt(p_password, v_password_hash) THEN
    -- Update last login timestamp
    UPDATE customers SET last_login = now() WHERE id = v_customer_id;
    RETURN v_customer_id;
  END IF;

  RETURN NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;