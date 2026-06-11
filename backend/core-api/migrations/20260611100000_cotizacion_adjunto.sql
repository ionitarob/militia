CREATE TABLE cotizacion_adjunto (
    id            SERIAL PRIMARY KEY,
    licitacion_id INT  NOT NULL REFERENCES licitacion(id) ON DELETE CASCADE,
    nombre        TEXT NOT NULL,
    s3_key        TEXT NOT NULL,
    content_type  TEXT,
    size_bytes    BIGINT,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (licitacion_id, s3_key)
);
CREATE INDEX idx_cotizacion_adjunto_lic ON cotizacion_adjunto(licitacion_id);
