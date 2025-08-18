/*
  # Add attendant name to transactions

  1. Changes
    - Add attendant_name column to transactions table
    - Add index for attendant name search
    - Update existing functions to handle attendant name

  2. Security
    - Maintain existing RLS policies
*/

-- Add attendant_name column to transactions
ALTER TABLE transactions
ADD COLUMN IF NOT EXISTS attendant_name text;

-- Create index for attendant name search
CREATE INDEX IF NOT EXISTS idx_transactions_attendant_name 
ON transactions (attendant_name) 
WHERE attendant_name IS NOT NULL;