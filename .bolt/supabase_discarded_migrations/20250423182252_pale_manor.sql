/*
  # Fix password reset to use phone and date of birth

  1. Changes
    - Update reset_customer_password_with_dob function to use both phone and date of birth
    - Ensure unique customer identification
    - Maintain proper password hashing

  2. Security
    - Use both phone and date of birth for verification
    - Continue using bcrypt for password hashing
*/

-- Drop existing function
DROP FUNCTION IF EXISTS reset_customer_password_with_dob(date, text);

-- Create updated function with proper customer identification
CREATE OR REPLACE FUNCTION reset_customer_password_with_dob(
  p_phone text,
  p_date_of_birth date,
  p_new_password text
)
RETURNS boolean AS $$
DECLARE
  v_customer_id uuid;
BEGIN
  -- Find customer with matching phone and date of birth
  SELECT id INTO v_customer_id
  FROM customers
  WHERE phone = p_phone
    AND date_of_birth = p_date_of_birth;

  -- Check if customer exists
  IF v_customer_id IS NULL THEN
    RETURN false;
  END IF;

  -- Update password with proper hashing using bcrypt
  UPDATE customers
  SET password_hash = crypt(p_new_password, gen_salt('bf'))
  WHERE id = v_customer_id;

  RETURN true;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Add comment to function
COMMENT ON FUNCTION reset_customer_password_with_dob IS 'Resets customer password using phone and date of birth verification, with proper bcrypt password hashing';