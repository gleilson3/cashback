/*
  # Add store_id to admins table

  1. Changes
    - Add store_id column to admins table
    - Add foreign key constraint to stores table
    - Update existing RLS policies

  2. Security
    - Maintain existing RLS policies
    - Add store-based access control
*/

-- Add store_id column to admins table
ALTER TABLE admins
ADD COLUMN store_id uuid REFERENCES stores(id);

-- Create index for store lookups
CREATE INDEX IF NOT EXISTS idx_admins_store_id 
ON admins (store_id) 
WHERE store_id IS NOT NULL;

-- Update RLS policies for admins
DROP POLICY IF EXISTS "Admins can read own data" ON admins;

CREATE POLICY "Admins can read own data"
  ON admins
  FOR SELECT
  TO authenticated
  USING (auth.uid() = id);

-- Add function to get admin's store
CREATE OR REPLACE FUNCTION get_admin_store()
RETURNS uuid AS $$
BEGIN
  RETURN (
    SELECT store_id 
    FROM admins 
    WHERE id = auth.uid()
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Update transactions policies
DROP POLICY IF EXISTS "Enable read access for all users" ON transactions;
DROP POLICY IF EXISTS "Enable update access for authenticated users" ON transactions;

CREATE POLICY "Admins can view transactions from their store"
  ON transactions
  FOR SELECT
  TO authenticated
  USING (
    -- Allow access if admin has store_id and transaction matches their store
    (EXISTS (
      SELECT 1 FROM admins 
      WHERE id = auth.uid() 
      AND store_id = transactions.store_id
    ))
    OR
    -- Or if admin has special access (no store_id assigned)
    (EXISTS (
      SELECT 1 FROM admins 
      WHERE id = auth.uid() 
      AND store_id IS NULL
    ))
  );

CREATE POLICY "Admins can update transactions from their store"
  ON transactions
  FOR UPDATE
  TO authenticated
  USING (
    -- Allow access if admin has store_id and transaction matches their store
    (EXISTS (
      SELECT 1 FROM admins 
      WHERE id = auth.uid() 
      AND store_id = transactions.store_id
    ))
    OR
    -- Or if admin has special access (no store_id assigned)
    (EXISTS (
      SELECT 1 FROM admins 
      WHERE id = auth.uid() 
      AND store_id IS NULL
    ))
  );

-- Add comment
COMMENT ON FUNCTION get_admin_store IS 'Returns the store ID associated with the current admin user';