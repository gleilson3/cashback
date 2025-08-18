/*
  # Create store records

  1. New Records
    - Creates store records with matching IDs from the frontend
    - Ensures store IDs exist for transactions

  2. Changes
    - Inserts store records with predefined UUIDs
    - Sets up required store data
*/

-- Insert store records with matching IDs from the frontend
INSERT INTO stores (id, name, code, password_hash, created_at)
VALUES 
  ('550e8400-e29b-41d4-a716-446655440000', 'Loja 1', 'STORE1', crypt('store1password', gen_salt('bf')), now()),
  ('550e8400-e29b-41d4-a716-446655440001', 'Loja 2', 'STORE2', crypt('store2password', gen_salt('bf')), now()),
  ('550e8400-e29b-41d4-a716-446655440002', 'Loja Teste', 'STORE_TEST', crypt('testpassword', gen_salt('bf')), now())
ON CONFLICT (id) DO NOTHING;