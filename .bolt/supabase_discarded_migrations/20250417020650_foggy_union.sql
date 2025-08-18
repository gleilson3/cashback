/*
  # Add password recovery functionality

  1. Changes
    - Add reset_token column to customers table
    - Add reset_token_expires_at column to customers table
    - Add function to generate and store reset token
    - Add function to verify and reset password

  2. Security
    - Tokens expire after 1 hour
    - Tokens are one-time use only
    - Secure password reset process
*/

-- Add columns for password reset
ALTER TABLE customers
ADD COLUMN IF NOT EXISTS reset_token text,
ADD COLUMN IF NOT EXISTS reset_token_expires_at timestamptz;

-- Create function to generate reset token
CREATE OR REPLACE FUNCTION generate_customer_reset_token(p_phone text)
RETURNS text AS $$
DECLARE
  v_token text;
  v_customer_id uuid;
BEGIN
  -- Check if phone exists
  SELECT id INTO v_customer_id
  FROM customers
  WHERE phone = p_phone;

  IF v_customer_id IS NULL THEN
    RAISE EXCEPTION 'Phone number not found';
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
  p_phone text,
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
  WHERE phone = p_phone
    AND reset_token = p_token
    AND reset_token_expires_at > now();

  IF v_customer_id IS NULL THEN
    RETURN false;
  END IF;

  -- Reset password and clear token
  UPDATE customers
  SET password_hash = p_new_password,
      reset_token = NULL,
      reset_token_expires_at = NULL
  WHERE id = v_customer_id;

  RETURN true;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;