/*
  # Fix password reset functionality

  1. Changes
    - Drop existing password reset function
    - Create new function that properly hashes the password
    - Add phone number parameter for customer lookup
    - Improve error handling

  2. Security
    - Ensure password is properly hashed
    - Validate date of birth match
*/

-- Drop existing function
DROP FUNCTION IF EXISTS reset_customer_password_with_dob(date, text);

-- Create new function with proper password hashing
CREATE OR REPLACE FUNCTION reset_customer_password_with_dob(
  p_phone text,
  p_date_of_birth date,
  p_new_password text
)
RETURNS boolean AS $$
DECLARE
  v_customer_id uuid;
  v_stored_dob date;
BEGIN
  -- Find customer with matching phone and get their date of birth
  SELECT id, date_of_birth INTO v_customer_id, v_stored_dob
  FROM customers
  WHERE phone = p_phone;

  -- Check if customer exists
  IF v_customer_id IS NULL THEN
    RETURN false;
  END IF;

  -- Verify date of birth matches
  IF v_stored_dob != p_date_of_birth THEN
    RETURN false;
  END IF;

  -- Update password with proper hashing
  UPDATE customers
  SET password_hash = crypt(p_new_password, gen_salt('bf'))
  WHERE id = v_customer_id;

  RETURN true;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Add comment to function
COMMENT ON FUNCTION reset_customer_password_with_dob IS 'Resets customer password using phone number and date of birth verification, with proper password hashing';