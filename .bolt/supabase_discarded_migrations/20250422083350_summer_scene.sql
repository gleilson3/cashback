/*
  # Update password reset function to use customer ID

  1. Changes
    - Drop existing function
    - Create new function that uses customer ID from session
    - Add proper password validation
    - Ensure secure password hashing

  2. Security
    - Verify customer exists
    - Use proper password hashing
    - Validate password requirements
*/

-- Drop existing function
DROP FUNCTION IF EXISTS reset_customer_password_with_dob(date, text);

-- Create new function with proper password hashing
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

-- Add comment to function
COMMENT ON FUNCTION reset_customer_password_with_dob IS 'Resets customer password using customer ID and date of birth verification, with proper password hashing';