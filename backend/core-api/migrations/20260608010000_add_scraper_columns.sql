-- Migration 002 – Add external_id and scraper-populated columns

ALTER TABLE licitacion
  ADD COLUMN IF NOT EXISTS external_id      TEXT UNIQUE,
  ADD COLUMN IF NOT EXISTS tipo_tramitacion TEXT,
  ADD COLUMN IF NOT EXISTS valor_estimado   NUMERIC(15,2);

ALTER TABLE adjudicacion
  ADD COLUMN IF NOT EXISTS external_id               TEXT UNIQUE,
  ADD COLUMN IF NOT EXISTS tipo_tramitacion          TEXT,
  ADD COLUMN IF NOT EXISTS valor_estimado            NUMERIC(15,2),
  ADD COLUMN IF NOT EXISTS importe_adjudicado        NUMERIC(15,2),
  ADD COLUMN IF NOT EXISTS fecha_vencimiento_contrato DATE;
