/*
  # Add function to get database current date

  1. Changes
    - Add function to return current database timestamp
    - Add function to return current database timezone

  2. Security
    - Maintain existing RLS policies
*/

-- Create function to get current database timestamp
CREATE OR REPLACE FUNCTION get_database_timestamp()
RETURNS timestamp with time zone AS $$
BEGIN
  RETURN CURRENT_TIMESTAMP;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create function to get current database timezone
CREATE OR REPLACE FUNCTION get_database_timezone()
RETURNS text AS $$
BEGIN
  RETURN current_setting('TIMEZONE');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Add comments
COMMENT ON FUNCTION get_database_timestamp IS 'Returns the current database timestamp';
COMMENT ON FUNCTION get_database_timezone IS 'Returns the current database timezone setting';