/*
  # Add PIX transaction fields to credits table

  1. Changes
    - Add pix_transaction_id column
    - Add index for PIX transaction lookup
    - Add validation for PIX transactions

  2. Security
    - Maintain existing RLS policies
*/

-- Add PIX transaction ID column
ALTER TABLE credits
ADD COLUMN IF NOT EXISTS pix_transaction_id text;

-- Create index for PIX transaction lookup
CREATE INDEX IF NOT EXISTS idx_credits_pix_transaction 
ON credits (pix_transaction_id) 
WHERE pix_transaction_id IS NOT NULL;