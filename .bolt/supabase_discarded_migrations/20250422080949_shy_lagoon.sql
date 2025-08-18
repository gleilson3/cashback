/*
  # Update password reset to use date of birth verification

  1. Changes
    - Remove email-based password reset
    - Create new function to reset password using date of birth
    - Remove token-based verification
    - Simplify password reset process

  2. Security
    - Verify date of birth matches exactly
    - Maintain password hashing security
*/

-- Drop existing functions
DROP FUNCTION IF EXISTS reset_customer_password(text, text, text, date);
DROP FUNCTION IF EXISTS generate_customer_reset_token(text);

-- Create new function for password reset with date of birth
CREATE OR REPLACE FUNCTION reset_customer_password_with_dob(
  p_date_of_birth date,
  p_new_password text
)
RETURNS boolean AS $$
DECLARE
  v_customer_id uuid;
BEGIN
  -- Find customer with matching date of birth
  SELECT id INTO v_customer_id
  FROM customers
  WHERE date_of_birth = p_date_of_birth;

  IF v_customer_id IS NULL THEN
    RETURN false;
  END IF;

  -- Update password
  UPDATE customers
  SET password_hash = p_new_password
  WHERE id = v_customer_id;

  RETURN true;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Remove unused columns
ALTER TABLE customers
DROP COLUMN IF EXISTS reset_token,
DROP COLUMN IF EXISTS reset_token_expires_at;

-- Add comment to function
COMMENT ON FUNCTION reset_customer_password_with_dob IS 'Resets customer password using date of birth verification';