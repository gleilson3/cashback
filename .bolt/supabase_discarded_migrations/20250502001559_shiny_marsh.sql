/*
  # Add receipt URL field to transactions table

  1. Changes
    - Add receipt_url column to transactions table
    - Add index for receipt lookups
    - Update RLS policies

  2. Security
    - Maintain existing RLS policies
*/

-- Add receipt_url column to transactions table
ALTER TABLE transactions
ADD COLUMN IF NOT EXISTS receipt_url text;

-- Create index for receipt lookups
CREATE INDEX IF NOT EXISTS idx_transactions_receipt_url 
ON transactions (receipt_url) 
WHERE receipt_url IS NOT NULL;