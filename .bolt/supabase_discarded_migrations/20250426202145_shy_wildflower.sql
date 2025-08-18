/*
  # Add credits system tables and functions

  1. New Tables
    - `credits`
      - `id` (uuid, primary key)
      - `customer_id` (uuid, foreign key)
      - `amount` (decimal)
      - `expires_at` (timestamp)
      - `created_at` (timestamp)
      - `status` (text)

  2. Security
    - Enable RLS on credits table
    - Add policies for authenticated users
*/

-- Create credits table
CREATE TABLE IF NOT EXISTS credits (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_id uuid REFERENCES customers(id) NOT NULL,
  amount decimal NOT NULL CHECK (amount >= 10), -- Minimum R$10
  expires_at timestamptz NOT NULL,
  created_at timestamptz DEFAULT now(),
  status text NOT NULL CHECK (status IN ('pending', 'approved', 'rejected')),
  payment_method text NOT NULL CHECK (payment_method IN ('pix', 'credit_card', 'debit_card', 'cash'))
);

-- Enable RLS
ALTER TABLE credits ENABLE ROW LEVEL SECURITY;

-- Create policies
CREATE POLICY "Enable insert access for all users"
  ON credits
  FOR INSERT
  TO public
  WITH CHECK (true);

CREATE POLICY "Enable read access for all users"
  ON credits
  FOR SELECT
  TO public
  USING (true);

CREATE POLICY "Enable update access for authenticated users"
  ON credits
  FOR UPDATE
  TO authenticated
  USING (true);

-- Create function to get available credits
CREATE OR REPLACE FUNCTION get_available_credits(p_customer_id uuid)
RETURNS decimal AS $$
DECLARE
  v_credits decimal;
BEGIN
  SELECT COALESCE(SUM(amount), 0)
  INTO v_credits
  FROM credits
  WHERE customer_id = p_customer_id
    AND status = 'approved'
    AND expires_at > CURRENT_TIMESTAMP;
    
  RETURN v_credits;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Add comment
COMMENT ON FUNCTION get_available_credits IS 'Calculates available credits for a customer';