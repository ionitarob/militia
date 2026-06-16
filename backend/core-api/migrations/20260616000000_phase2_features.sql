-- ── Phase II features ─────────────────────────────────────────────────────────

-- 1. Stage history: track every pipeline_stage change with timestamp + author
CREATE TABLE IF NOT EXISTS licitacion_stage_history (
    id            BIGSERIAL PRIMARY KEY,
    licitacion_id BIGINT NOT NULL REFERENCES licitacion(id) ON DELETE CASCADE,
    stage         TEXT   NOT NULL,
    changed_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    changed_by    BIGINT REFERENCES app_user(id)
);
CREATE INDEX IF NOT EXISTS licitacion_stage_history_licitacion_id_changed_at_idx ON licitacion_stage_history(licitacion_id, changed_at DESC);

-- 2. Rejection reason when stage = 'perdida'
ALTER TABLE licitacion
    ADD COLUMN IF NOT EXISTS motivo_perdida       TEXT,   -- 'fabricante' | 'otro'
    ADD COLUMN IF NOT EXISTS motivo_perdida_texto  TEXT;  -- free text when 'otro'

-- 3. Manufacturer protection per licitacion
ALTER TABLE licitacion
    ADD COLUMN IF NOT EXISTS fabricante_proteccion BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS fabricante_nombre     TEXT;

-- 4. Multiple active assignments: drop the single-active partial index so many
--    comerciales can be co-assigned simultaneously.
DROP INDEX IF EXISTS licitacion_assignment_active_idx;
-- Keep a plain index for lookup performance
CREATE INDEX IF NOT EXISTS licitacion_assignment_licitacion_idx
    ON licitacion_assignment(licitacion_id) WHERE active = TRUE;

-- 5. Move ingram workflow fields per-client (estado, division, fabricante protection)
ALTER TABLE licitacion_cotizacion
    ADD COLUMN IF NOT EXISTS estado                TEXT,
    ADD COLUMN IF NOT EXISTS division              TEXT,
    ADD COLUMN IF NOT EXISTS fabricante_proteccion BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS fabricante_nombre     TEXT;
