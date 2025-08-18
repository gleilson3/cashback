/*
  # Update password reset to use date of birth verification

  1. Changes
    - Drop existing functions
    - Create new function to reset password with date of birth
    - Remove token-based verification
    - Simplify password reset process

  2. Security
    - Verify date of birth matches exactly
    - Maintain password hashing security
*/

-- Drop existing functions
DROP FUNCTION IF EXISTS reset_customer_password(text, text, text);
DROP FUNCTION IF EXISTS generate_customer_reset_token(text);

-- Create new function for password reset with date of birth
CREATE OR REPLACE FUNCTION reset_customer_password_with_dob(
  p_customer_id uuid,
  p_date_of_birth date,
  p_new_password text
)
RETURNS boolean AS $$
DECLARE
  v_stored_dob date;
BEGIN
  -- Get stored date of birth for customer
  SELECT date_of_birth INTO v_stored_dob
  FROM customers
  WHERE id = p_customer_id;

  -- Check if customer exists and dates match
  IF v_stored_dob IS NULL OR v_stored_dob != p_date_of_birth THEN
    RETURN false;
  END IF;

  -- Update password with proper hashing
  UPDATE customers
  SET password_hash = crypt(p_new_password, gen_salt('bf'))
  WHERE id = p_customer_id;

  RETURN true;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Remove unused columns
ALTER TABLE customers
DROP COLUMN IF EXISTS reset_token,
DROP COLUMN IF EXISTS reset_token_expires_at;

-- Add comment to function
COMMENT ON FUNCTION reset_customer_password_with_dob IS 'Resets customer password using customer ID and date of birth verification, with proper password hashing';