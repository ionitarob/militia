-- ============================================================
-- IMLiti – Ingram Workflow Fields
-- Migration 004 – Ingram workflow + enhanced client cotizacion
-- ============================================================

-- Ingram-specific sales workflow fields on licitacion
ALTER TABLE licitacion
  ADD COLUMN IF NOT EXISTS ingram_estado           TEXT,
  ADD COLUMN IF NOT EXISTS ingram_owner            TEXT,
  ADD COLUMN IF NOT EXISTS cotizacion_solicitada_a TEXT;

-- Allow orden to be NULL so new rows from the app can omit it
ALTER TABLE licitacion_cotizacion ALTER COLUMN orden DROP NOT NULL;

-- Add XV quote name and opportunity columns
ALTER TABLE licitacion_cotizacion
  ADD COLUMN IF NOT EXISTS cotizacion_xv  TEXT,
  ADD COLUMN IF NOT EXISTS oportunidad    TEXT;

-- Replace order-based unique key with (licitacion_id, cliente_nombre) key
ALTER TABLE licitacion_cotizacion
  DROP CONSTRAINT IF EXISTS licitacion_cotizacion_licitacion_id_orden_key;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'licitacion_cotizacion_licitacion_cliente_key'
  ) THEN
    ALTER TABLE licitacion_cotizacion
      ADD CONSTRAINT licitacion_cotizacion_licitacion_cliente_key
      UNIQUE (licitacion_id, cliente_nombre);
  END IF;
END$$;
