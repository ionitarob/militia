-- Alerts sent to comerciales when a licitacion they worked on gets adjudicada
CREATE TABLE IF NOT EXISTS alerta (
  id              BIGSERIAL    PRIMARY KEY,
  user_id         INT          NOT NULL REFERENCES usuarios(id) ON DELETE CASCADE,
  adjudicacion_id BIGINT       NOT NULL REFERENCES adjudicacion(id) ON DELETE CASCADE,
  licitacion_id   BIGINT       REFERENCES licitacion(id) ON DELETE SET NULL,
  mensaje         TEXT         NOT NULL,
  leida           BOOLEAN      NOT NULL DEFAULT FALSE,
  created_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX idx_alerta_unique ON alerta (user_id, adjudicacion_id);
CREATE INDEX idx_alerta_user_leida      ON alerta (user_id, leida);
CREATE INDEX idx_alerta_adjudicacion_id ON alerta (adjudicacion_id);
