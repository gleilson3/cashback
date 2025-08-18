/*
  # Update password reset to use email

  1. Changes
    - Add email column to customers table
    - Add function to generate reset token
    - Add function to reset password with token
    - Add email format validation

  2. Security
    - Tokens expire after 1 hour
    - Secure password reset process
    - Email format validation
*/

-- Add email column if it doesn't exist
ALTER TABLE customers
ADD COLUMN IF NOT EXISTS email text,
ADD COLUMN IF NOT EXISTS reset_token text,
ADD COLUMN IF NOT EXISTS reset_token_expires_at timestamptz;

-- Add email format check
ALTER TABLE customers
ADD CONSTRAINT customers_email_format_check 
CHECK (email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$');

-- Create index for email lookups
CREATE INDEX IF NOT EXISTS idx_customers_email 
ON customers (email) 
WHERE email IS NOT NULL;

-- Create function to generate reset token
CREATE OR REPLACE FUNCTION generate_customer_reset_token(p_email text)
RETURNS text AS $$
DECLARE
  v_token text;
  v_customer_id uuid;
BEGIN
  -- Check if email exists
  SELECT id INTO v_customer_id
  FROM customers
  WHERE email = p_email;

  IF v_customer_id IS NULL THEN
    RAISE EXCEPTION 'Email not found';
  END IF;

  -- Generate token
  v_token := encode(gen_random_bytes(32), 'hex');

  -- Store token with expiration
  UPDATE customers
  SET reset_token = v_token,
      reset_token_expires_at = now() + interval '1 hour'
  WHERE id = v_customer_id;

  RETURN v_token;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create function to reset password
CREATE OR REPLACE FUNCTION reset_customer_password(
  p_email text,
  p_token text,
  p_new_password text
)
RETURNS boolean AS $$
DECLARE
  v_customer_id uuid;
BEGIN
  -- Find customer with valid token
  SELECT id INTO v_customer_id
  FROM customers
  WHERE email = p_email
    AND reset_token = p_token
    AND reset_token_expires_at > now();

  IF v_customer_id IS NULL THEN
    RETURN false;
  END IF;

  -- Reset password and clear token
  UPDATE customers
  SET password_hash = crypt(p_new_password, gen_salt('bf')),
      reset_token = NULL,
      reset_token_expires_at = NULL
  WHERE id = v_customer_id;

  RETURN true;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;