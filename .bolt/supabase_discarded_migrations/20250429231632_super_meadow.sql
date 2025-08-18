/*
  # Update admin authentication to use phone number

  1. Changes
    - Add phone column to admins table
    - Add phone format validation
    - Add function to verify admin password with phone
    - Update existing functions

  2. Security
    - Maintain existing RLS policies
    - Add proper validation
*/

-- Add phone column to admins table
ALTER TABLE admins
ADD COLUMN IF NOT EXISTS phone text UNIQUE;

-- Add phone format check
ALTER TABLE admins
ADD CONSTRAINT admins_phone_format_check 
CHECK (phone ~ '^\d{11}$');

-- Create function to verify admin password
CREATE OR REPLACE FUNCTION verify_admin_password(
  p_phone text,
  p_password text
)
RETURNS uuid AS $$
DECLARE
  v_admin_id uuid;
  v_password_hash text;
BEGIN
  -- Get admin password hash
  SELECT id, password_hash 
  INTO v_admin_id, v_password_hash
  FROM admins
  WHERE phone = p_phone;

  -- Check if admin exists and verify password
  IF v_admin_id IS NOT NULL AND 
     v_password_hash = crypt(p_password, v_password_hash) THEN
    -- Update last login timestamp
    UPDATE admins
    SET last_login = now()
    WHERE id = v_admin_id;
    
    RETURN v_admin_id;
  END IF;

  RETURN NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Add comment
COMMENT ON FUNCTION verify_admin_password IS 'Verifies admin password using phone number and returns admin ID if valid';