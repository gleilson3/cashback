/*
  # Add location column to transactions table

  1. Changes
    - Add `location` column to `transactions` table of type JSONB to store latitude and longitude coordinates
    - Column is nullable since not all transactions require location data
    - Add B-tree index on the location column for better query performance
  
  2. Notes
    - Using JSONB type for flexible storage of location data
    - Location data will be stored in format: { "latitude": number, "longitude": number }
*/

-- Add location column if it doesn't exist
DO $$ 
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'transactions' 
    AND column_name = 'location'
  ) THEN
    ALTER TABLE transactions 
    ADD COLUMN location JSONB;

    -- Create a btree index for the location column
    CREATE INDEX IF NOT EXISTS idx_transactions_location 
    ON transactions USING btree ((location->>'latitude'), (location->>'longitude'));

    -- Add comment explaining the column usage
    COMMENT ON COLUMN transactions.location IS 'Stores transaction location data as JSONB with latitude and longitude';
  END IF;
END $$;