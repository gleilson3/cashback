/*
  # Add WhatsApp consent field to customers table

  1. Changes
    - Add whatsapp_consent column to customers table
    - Add default value of false
    - Update existing customers to have consent as false

  2. Security
    - Maintain existing RLS policies
*/

-- Add whatsapp_consent column to customers table
ALTER TABLE customers
ADD COLUMN IF NOT EXISTS whatsapp_consent boolean DEFAULT false;

-- Update existing customers to have consent as false
UPDATE customers
SET whatsapp_consent = false
WHERE whatsapp_consent IS NULL;