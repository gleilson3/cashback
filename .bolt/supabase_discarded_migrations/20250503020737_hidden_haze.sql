/*
  # Add sessions tracking table and functions

  1. New Tables
    - `active_sessions`
      - `id` (uuid, primary key)
      - `user_id` (uuid, foreign key)
      - `last_seen` (timestamp)
      - `created_at` (timestamp)

  2. Functions
    - Function to update session activity
    - Function to clean up expired sessions
    - Function to get active user count

  3. Security
    - Enable RLS on sessions table
    - Add policies for authenticated users
*/

-- Create active sessions table
CREATE TABLE IF NOT EXISTS active_sessions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES customers(id) ON DELETE CASCADE,
  last_seen timestamptz DEFAULT now(),
  created_at timestamptz DEFAULT now()
);

-- Enable RLS
ALTER TABLE active_sessions ENABLE ROW LEVEL SECURITY;

-- Create policies
CREATE POLICY "Enable insert access for all users"
  ON active_sessions
  FOR INSERT
  TO public
  WITH CHECK (true);

CREATE POLICY "Enable read access for all users"
  ON active_sessions
  FOR SELECT
  TO public
  USING (true);

CREATE POLICY "Enable update access for authenticated users"
  ON active_sessions
  FOR UPDATE
  TO authenticated
  USING (true);

-- Function to update session activity
CREATE OR REPLACE FUNCTION update_session_activity(p_user_id uuid)
RETURNS void AS $$
BEGIN
  INSERT INTO active_sessions (user_id)
  VALUES (p_user_id)
  ON CONFLICT (id) DO UPDATE
  SET last_seen = now();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to clean up expired sessions (older than 5 minutes)
CREATE OR REPLACE FUNCTION cleanup_expired_sessions()
RETURNS void AS $$
BEGIN
  DELETE FROM active_sessions
  WHERE last_seen < now() - interval '5 minutes';
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to get active user count
CREATE OR REPLACE FUNCTION get_active_users_count()
RETURNS integer AS $$
BEGIN
  -- Clean up expired sessions first
  PERFORM cleanup_expired_sessions();
  
  -- Return count of active sessions
  RETURN (
    SELECT COUNT(DISTINCT user_id)
    FROM active_sessions
    WHERE last_seen > now() - interval '5 minutes'
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create index for performance
CREATE INDEX IF NOT EXISTS idx_active_sessions_last_seen 
ON active_sessions (last_seen);

-- Add comment
COMMENT ON TABLE active_sessions IS 'Tracks active user sessions';