-- ── Cotizacion V2 ─────────────────────────────────────────────────────────────

-- 1. Multiple divisions (array) + client-presentation flag
ALTER TABLE licitacion_cotizacion
    ADD COLUMN IF NOT EXISTS divisiones  TEXT[]  NOT NULL DEFAULT '{}',
    ADD COLUMN IF NOT EXISTS se_presenta BOOLEAN NOT NULL DEFAULT FALSE;

-- Migrate existing single division → array
UPDATE licitacion_cotizacion
SET divisiones = ARRAY[division]
WHERE division IS NOT NULL AND cardinality(divisiones) = 0;

-- 2. Per-user rows: each assignee gets their own cotizacion record per client
ALTER TABLE licitacion_cotizacion
    ADD COLUMN IF NOT EXISTS user_id BIGINT REFERENCES app_user(id);

-- Drop old unique constraint (licitacion_id, cliente_nombre)
ALTER TABLE licitacion_cotizacion
    DROP CONSTRAINT IF EXISTS licitacion_cotizacion_licitacion_id_cliente_nombre_key;

-- New unique index: NULL user_id treated as sentinel -1 so it still enforces uniqueness
CREATE UNIQUE INDEX IF NOT EXISTS uq_cotizacion_per_user
    ON licitacion_cotizacion(licitacion_id, cliente_nombre, COALESCE(user_id, -1));

-- 3. Change-history log
CREATE TABLE IF NOT EXISTS cotizacion_cambio (
    id             BIGSERIAL    PRIMARY KEY,
    licitacion_id  BIGINT       NOT NULL REFERENCES licitacion(id) ON DELETE CASCADE,
    cliente_nombre TEXT         NOT NULL,
    user_id        BIGINT       REFERENCES app_user(id),
    user_nombre    TEXT,
    campo          TEXT         NOT NULL,
    valor_antes    TEXT,
    valor_despues  TEXT,
    cambiado_en    TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_cotizacion_cambio_lid
    ON cotizacion_cambio(licitacion_id, cambiado_en DESC);
