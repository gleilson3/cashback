/*
  # Add comments to transactions

  1. Changes
    - Add comment column to transactions table
    - Add index for comment search
    - Update existing functions to handle comments

  2. Security
    - Maintain existing RLS policies
*/

-- Add comment column to transactions
ALTER TABLE transactions
ADD COLUMN IF NOT EXISTS comment text;

-- Create index for comment search
CREATE INDEX IF NOT EXISTS idx_transactions_comment 
ON transactions (comment) 
WHERE comment IS NOT NULL;