-- Drop existing policies
DROP POLICY IF EXISTS "Admins can view transactions from their store" ON transactions;
DROP POLICY IF EXISTS "Admins can update transactions from their store" ON transactions;
DROP POLICY IF EXISTS "Admins can read own data" ON admins;

-- Drop store-related columns and functions
ALTER TABLE admins
DROP COLUMN IF EXISTS store_id;

DROP INDEX IF EXISTS idx_admins_store_id;
DROP FUNCTION IF EXISTS get_admin_store();

-- Restore original policies
CREATE POLICY "Enable read access for all users"
  ON transactions
  FOR SELECT
  TO public
  USING (true);

CREATE POLICY "Enable update access for authenticated users"
  ON transactions
  FOR UPDATE
  TO authenticated
  USING (true);

CREATE POLICY "Admins can read own data"
  ON admins
  FOR SELECT
  TO authenticated
  USING (auth.uid() = id);