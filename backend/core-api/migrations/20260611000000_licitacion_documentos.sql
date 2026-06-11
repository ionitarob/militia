CREATE TABLE licitacion_documento (
    id            SERIAL PRIMARY KEY,
    licitacion_id INT  NOT NULL REFERENCES licitacion(id) ON DELETE CASCADE,
    nombre        TEXT NOT NULL,
    s3_key        TEXT NOT NULL,
    content_type  TEXT,
    size_bytes    BIGINT,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (licitacion_id, s3_key)
);

CREATE INDEX idx_licitacion_documento_lic ON licitacion_documento(licitacion_id);
