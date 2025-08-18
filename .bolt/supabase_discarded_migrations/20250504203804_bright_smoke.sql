/*
  # Create store locations

  1. Changes
    - Insert store records for existing locations
    - Add store passwords for authentication

  2. Security
    - Store passwords will be automatically hashed by the trigger
*/

INSERT INTO stores (id, name, code, password_hash)
VALUES 
  ('123e4567-e89b-12d3-a456-426614174000', 'Loja 1: Rua Dois, 2130‑A, Residencial 1 – Cágado', 'LOJA1', 'store1password'),
  ('123e4567-e89b-12d3-a456-426614174001', 'Loja 2: Rua Um, 1614‑C, Residencial 1 – Cágado', 'LOJA2', 'store2password')
ON CONFLICT (id) DO NOTHING;