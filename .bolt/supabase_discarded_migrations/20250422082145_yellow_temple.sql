-- Drop existing function
DROP FUNCTION IF EXISTS reset_customer_password_with_dob(text, date, text);

-- Create new function with proper password hashing
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

  -- Check if customer exists
  IF v_customer_id IS NULL THEN
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
COMMENT ON FUNCTION reset_customer_password_with_dob IS 'Resets customer password using date of birth verification, with proper password hashing';