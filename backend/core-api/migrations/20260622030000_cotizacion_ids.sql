ALTER TABLE licitacion_cotizacion
    ADD COLUMN IF NOT EXISTS cotizacion_id  TEXT,
    ADD COLUMN IF NOT EXISTS oportunidad_id TEXT;
