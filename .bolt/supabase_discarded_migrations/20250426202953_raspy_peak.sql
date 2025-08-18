-- Add stripe_session_id to credits table
ALTER TABLE credits
ADD COLUMN stripe_session_id text;

-- Create index for stripe_session_id
CREATE INDEX IF NOT EXISTS idx_credits_stripe_session 
ON credits (stripe_session_id) 
WHERE stripe_session_id IS NOT NULL;