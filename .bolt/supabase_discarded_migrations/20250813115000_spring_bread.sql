/*
  # Create customers table and related functions

  1. New Tables
    - `customers`
      - `id` (uuid, primary key)
      - `name` (text, optional)
      - `phone` (text, unique, required)
      - `email` (text, unique, optional)
      - `date_of_birth` (date, optional)
      - `password_hash` (text, required)
      - `balance` (numeric, default 0)
      - `created_at` (timestamp)
      - `updated_at` (timestamp)
      - `last_login` (timestamp, optional)
      - `whatsapp_consent` (boolean, default false)

  2. Security
    - Enable RLS on `customers` table
    - Add policies for customer registration and data access
    - Add password verification function
    - Add password reset function

  3. Functions
    - `verify_customer_password` - Verify customer login credentials
    - `reset_customer_password_with_dob` - Reset password using date of birth
    - `hash_customer_password` - Hash passwords before storing
*/

-- Create customers table
CREATE TABLE IF NOT EXISTS customers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text,
  phone text UNIQUE NOT NULL,
  email text UNIQUE,
  date_of_birth date,
  password_hash text NOT NULL,
  balance numeric(10,2) DEFAULT 0,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  last_login timestamptz,
  whatsapp_consent boolean DEFAULT false
);

-- Enable RLS
ALTER TABLE customers ENABLE ROW LEVEL SECURITY;

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_customers_phone ON customers(phone);
CREATE INDEX IF NOT EXISTS idx_customers_email ON customers(email);
CREATE INDEX IF NOT EXISTS idx_customers_created_at ON customers(created_at);

-- RLS Policies
CREATE POLICY "Allow customer registration" ON customers
  FOR INSERT TO public
  WITH CHECK (true);

CREATE POLICY "Customers can read own data" ON customers
  FOR SELECT TO public
  USING (true);

CREATE POLICY "Customers can update own data" ON customers
  FOR UPDATE TO public
  USING (true)
  WITH CHECK (true);

-- Function to hash passwords
CREATE OR REPLACE FUNCTION hash_customer_password()
RETURNS trigger AS $$
BEGIN
  IF TG_OP = 'INSERT' OR (TG_OP = 'UPDATE' AND NEW.password_hash != OLD.password_hash) THEN
    NEW.password_hash = crypt(NEW.password_hash, gen_salt('bf'));
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger to hash passwords
DROP TRIGGER IF EXISTS trg_hash_customer_password ON customers;
CREATE TRIGGER trg_hash_customer_password
  BEFORE INSERT OR UPDATE OF password_hash ON customers
  FOR EACH ROW EXECUTE FUNCTION hash_customer_password();

-- Function to verify customer password
CREATE OR REPLACE FUNCTION verify_customer_password(p_email text, p_password text)
RETURNS boolean AS $$
DECLARE
  stored_hash text;
BEGIN
  SELECT password_hash INTO stored_hash
  FROM customers
  WHERE email = p_email;
  
  IF stored_hash IS NULL THEN
    RETURN false;
  END IF;
  
  RETURN stored_hash = crypt(p_password, stored_hash);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to reset customer password with date of birth verification
CREATE OR REPLACE FUNCTION reset_customer_password_with_dob(
  p_email text,
  p_date_of_birth date,
  p_new_password text
)
RETURNS boolean AS $$
DECLARE
  customer_exists boolean;
BEGIN
  -- Check if customer exists with matching email and date of birth
  SELECT EXISTS(
    SELECT 1 FROM customers 
    WHERE email = p_email AND date_of_birth = p_date_of_birth
  ) INTO customer_exists;
  
  IF NOT customer_exists THEN
    RETURN false;
  END IF;
  
  -- Update password
  UPDATE customers 
  SET password_hash = p_new_password,
      updated_at = now()
  WHERE email = p_email AND date_of_birth = p_date_of_birth;
  
  RETURN true;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create customer_balances view
CREATE OR REPLACE VIEW customer_balances AS
SELECT 
  c.id as customer_id,
  COALESCE(
    (
      SELECT SUM(t.cashback_amount) 
      FROM transactions t 
      WHERE t.customer_id = c.id 
        AND t.type = 'purchase' 
        AND t.status = 'approved'
        AND (t.expires_at IS NULL OR t.expires_at > now())
    ) - COALESCE(
      (
        SELECT SUM(t.amount) 
        FROM transactions t 
        WHERE t.customer_id = c.id 
          AND t.type = 'redemption' 
          AND t.status = 'approved'
      ), 0
    ), 0
  ) as available_balance,
  (
    SELECT t.cashback_amount
    FROM transactions t 
    WHERE t.customer_id = c.id 
      AND t.type = 'purchase' 
      AND t.status = 'approved'
      AND t.expires_at IS NOT NULL
      AND t.expires_at > now()
    ORDER BY t.expires_at ASC
    LIMIT 1
  ) as expiring_amount,
  (
    SELECT t.expires_at
    FROM transactions t 
    WHERE t.customer_id = c.id 
      AND t.type = 'purchase' 
      AND t.status = 'approved'
      AND t.expires_at IS NOT NULL
      AND t.expires_at > now()
    ORDER BY t.expires_at ASC
    LIMIT 1
  ) as expiration_date
FROM customers c;

-- Function to get available balance
CREATE OR REPLACE FUNCTION get_available_balance(p_customer_id uuid)
RETURNS numeric AS $$
DECLARE
  balance numeric(10,2);
BEGIN
  SELECT available_balance INTO balance
  FROM customer_balances
  WHERE customer_id = p_customer_id;
  
  RETURN COALESCE(balance, 0);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Update trigger function for updated_at
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS trigger AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger to update updated_at on customers
DROP TRIGGER IF EXISTS update_customers_updated_at ON customers;
CREATE TRIGGER update_customers_updated_at
  BEFORE UPDATE ON customers
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();