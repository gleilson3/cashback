/*
  # Add customer_id column to transactions table

  1. Changes
    - Add customer_id column to transactions table
    - Copy data from transactions_id to customer_id
    - Drop old transactions_id column
    - Handle balance validation by temporarily disabling trigger

  2. Security
    - Maintain foreign key constraints
    - Ensure data integrity during migration
*/

DO $$ 
DECLARE
  trigger_exists boolean;
BEGIN
  -- Check if the trigger exists
  SELECT EXISTS (
    SELECT 1 FROM pg_trigger 
    WHERE tgname = 'trg_handle_balance'
  ) INTO trigger_exists;

  -- Temporarily disable the balance trigger if it exists
  IF trigger_exists THEN
    ALTER TABLE transactions DISABLE TRIGGER trg_handle_balance;
  END IF;

  -- Add customer_id column if it doesn't exist
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'transactions'
    AND column_name = 'customer_id'
  ) THEN
    -- Add the new column
    ALTER TABLE transactions 
    ADD COLUMN customer_id uuid REFERENCES customers(id);

    -- Copy data from transactions_id to customer_id if transactions_id exists
    IF EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_name = 'transactions'
      AND column_name = 'transactions_id'
    ) THEN
      UPDATE transactions 
      SET customer_id = transactions_id;

      -- Drop the old column
      ALTER TABLE transactions 
      DROP COLUMN transactions_id;
    END IF;
  END IF;

  -- Re-enable the balance trigger if it was disabled
  IF trigger_exists THEN
    ALTER TABLE transactions ENABLE TRIGGER trg_handle_balance;
  END IF;
END $$;