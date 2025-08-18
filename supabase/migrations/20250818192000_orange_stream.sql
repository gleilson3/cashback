/*
  # Adicionar loja teste com coordenadas específicas

  1. New Store
    - `store_test` - Loja Teste
    - Coordenadas: 3°51'47.1"S 38°37'54.3"W
    - Convertidas para decimal: -3.8630833333333333, -38.63175

  2. Security
    - Utiliza as mesmas políticas RLS existentes da tabela stores
*/

-- Insert test store with specific coordinates
INSERT INTO stores (
  id,
  name,
  code,
  password_hash,
  address,
  phone,
  is_active,
  has_delivery,
  has_pos_sales,
  is_main_store
) VALUES (
  'store_test'::uuid,
  'Loja Teste',
  'TEST01',
  '$2b$10$defaulthashedpassword', -- Default hashed password
  'Localização de Teste - Coordenadas Específicas (3°51''47.1"S 38°37''54.3"W)',
  '(85) 99999-9999',
  true,
  true,
  true,
  false
) ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  address = EXCLUDED.address,
  phone = EXCLUDED.phone,
  is_active = EXCLUDED.is_active,
  has_delivery = EXCLUDED.has_delivery,
  has_pos_sales = EXCLUDED.has_pos_sales,
  is_main_store = EXCLUDED.is_main_store;