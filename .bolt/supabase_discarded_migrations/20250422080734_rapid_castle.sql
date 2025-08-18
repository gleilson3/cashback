/*
  # Update password reset function to include date of birth verification

  1. Changes
    - Modify reset_customer_password function to include date of birth check
    - Add date_of_birth parameter to function
    - Update verification logic to check date of birth

  2. Security
    - Maintain existing token security
    - Add additional verification layer with date of birth
*/

-- Drop existing function
DROP FUNCTION IF EXISTS reset_customer_password(text, text, text);

-- Create updated function with date of birth verification
CREATE OR REPLACE FUNCTION reset_customer_password(
  p_email text,
  p_token text,
  p_new_password text,
  p_date_of_birth date
)
RETURNS boolean AS $$
DECLARE
  v_customer_id uuid;
  v_customer_dob date;
BEGIN
  -- Find customer with valid token and get their date of birth
  SELECT id, date_of_birth INTO v_customer_id, v_customer_dob
  FROM customers
  WHERE email = p_email
    AND reset_token = p_token
    AND reset_token_expires_at > now();

  IF v_customer_id IS NULL THEN
    RETURN false;
  END IF;

  -- Verify date of birth matches
  IF v_customer_dob != p_date_of_birth THEN
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

-- Add comment to function
COMMENT ON FUNCTION reset_customer_password IS 'Resets customer password after verifying token and date of birth';