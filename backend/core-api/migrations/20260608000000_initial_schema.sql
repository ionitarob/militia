-- ============================================================
-- IMLiti Database Schema
-- PostgreSQL 16 (Aurora Serverless v2)
-- Migration 001 – Initial Schema
-- ============================================================

-- ── Enum Types ──────────────────────────────────────────────

CREATE TYPE ambito_geografico_tipo AS ENUM (
  'AGE',
  'Autónomo',
  'Local',
  'Otras entidades',
  'Provincial',
  'Red.Es',
  'Universidad'
);

CREATE TYPE comunidad_autonoma_tipo AS ENUM (
  'Andalucía',
  'Aragón',
  'Asturias Principado de',
  'Canarias',
  'Cantabria',
  'Castilla - La Mancha',
  'Castilla y León',
  'Catalunya',
  'Ceuta',
  'Comunitat Valenciana',
  'Extremadura',
  'Galicia',
  'Illes Balears',
  'Madrid Comunidad de',
  'Melilla',
  'Murcia Región de',
  'Navarra Comunidad Floral de',
  'País Vasco',
  'Rioja La'
);

CREATE TYPE tipo_procedimiento_tipo AS ENUM (
  'Abierto',
  'Acuerdo Marco',
  'Contrato Menor',
  'Diálogo Competitivo',
  'Negociado',
  'Negociado con Publicidad',
  'Negociado por exclusividad',
  'Negociado sin Publicidad',
  'Normas internas',
  'Restringido',
  'Simplificado',
  'Sistema Dinámico de Adquisición'
);

CREATE TYPE mercado_vertical_tipo AS ENUM (
  'CIENCIA E INNOVACIÓN',
  'DEFENSA',
  'ECONOMÍA Y HACIENDA',
  'EDUCACIÓN',
  'EDUCACIÓN CULTURA Y DEPORTES',
  'EMPLEO Y SEGURIDAD SOCIAL',
  'FOMENTO',
  'INDUSTRIA ENERGÍA Y TURISMO',
  'INFORMACIÓN Y COMUNICACIONES',
  'INTERIOR',
  'INTERIOR EMERGENCIAS Y PROTECCIÓN CIVIL',
  'JUSTICIA',
  'OTROS',
  'OTROS EELL',
  'SANIDAD',
  'TRANSPORTE'
);

CREATE TYPE plazo_oferta_estado_tipo AS ENUM (
  'En plazo de presentación',
  'Expiran en menos de 7 días',
  'Expiran en menos de 15 días',
  'Expiran en menos de 30 días'
);

-- Numbered so ORDER BY estado gives the natural workflow sequence
CREATE TYPE licitacion_estado_tipo AS ENUM (
  '1. PENDIENTE SOLICITUD DE COTIZACIÓN A PROVEEDOR',
  '2. COTIZACIÓN SOLICITADA (A PROVEEDOR)',
  '3. PENDIENTE ENVÍO DE COTIZACIÓN A CLIENTE',
  '4. COTIZACIÓN ENVIADA A CLIENTE - X4A',
  '5. RECHAZADO'
);

CREATE TYPE usuario_rol_tipo AS ENUM (
  'admin',
  'vendedor'
);

-- ── Reference / Lookup Tables ────────────────────────────────

CREATE TABLE usuarios (
  id         SERIAL              PRIMARY KEY,
  nombre     TEXT                NOT NULL,
  email      TEXT                NOT NULL UNIQUE,
  rol        usuario_rol_tipo    NOT NULL DEFAULT 'vendedor',
  activo     BOOLEAN             NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ         NOT NULL DEFAULT NOW()
);

-- 3-level technology taxonomy (sourced from GUIA GENERAL sheet)
CREATE TABLE area_tecnologica (
  id                SERIAL  PRIMARY KEY,
  cat1              TEXT    NOT NULL,
  cat2              TEXT    NOT NULL,
  cat3              TEXT    NOT NULL,
  posible_proveedor TEXT,
  UNIQUE (cat1, cat2, cat3)
);

-- European CPV procurement codes
CREATE TABLE cpv_code (
  code        VARCHAR(8)  PRIMARY KEY,
  descripcion TEXT        NOT NULL
);

-- Public bodies that issue tenders
CREATE TABLE organismo (
  id     SERIAL  PRIMARY KEY,
  nombre TEXT    NOT NULL UNIQUE
);

-- Internal supplier/partner companies flagged on each licitacion
CREATE TABLE proveedor_interno (
  id     SERIAL  PRIMARY KEY,
  nombre TEXT    NOT NULL UNIQUE
);

-- External companies that can win public contracts
CREATE TABLE adjudicatario (
  id     SERIAL  PRIMARY KEY,
  nombre TEXT    NOT NULL UNIQUE
);

-- ── Core Fact Tables ─────────────────────────────────────────

CREATE TABLE licitacion (
  id                        BIGSERIAL               PRIMARY KEY,

  fecha                     DATE                    NOT NULL,
  titulo                    TEXT                    NOT NULL,
  numero_expediente         TEXT                    NOT NULL,
  control_expediente        SMALLINT,
  subsanacion               TEXT,

  importe_licitacion        NUMERIC(15, 2),

  area_tecnologica_id       INT                     REFERENCES area_tecnologica(id),
  es_area_interes           BOOLEAN,

  ambito_geografico         ambito_geografico_tipo,
  comunidad_autonoma        comunidad_autonoma_tipo,
  provincia                 TEXT,

  organismo_id              INT                     REFERENCES organismo(id),
  mercado_vertical          mercado_vertical_tipo,
  competencia               TEXT,

  tipo_procedimiento        tipo_procedimiento_tipo,
  duracion_meses            SMALLINT,
  prorrogas_meses           SMALLINT,
  fecha_limite_oferta       TIMESTAMPTZ,
  plazo_oferta_estado       plazo_oferta_estado_tipo,

  puntos_precio             SMALLINT    CHECK (puntos_precio BETWEEN 0 AND 100),
  puntos_mejoras            SMALLINT    CHECK (puntos_mejoras BETWEEN 0 AND 100),
  puntos_subjetivos         SMALLINT    CHECK (puntos_subjetivos BETWEEN 0 AND 100),

  estado                    licitacion_estado_tipo,
  owner_id                  INT                     REFERENCES usuarios(id),

  proveedor_seleccionado    TEXT,
  proveedores_seleccionados TEXT,
  adjudicatario_nombre      TEXT,
  adjudicatario_otro        TEXT,
  comentarios               TEXT,

  created_at                TIMESTAMPTZ             NOT NULL DEFAULT NOW(),
  updated_at                TIMESTAMPTZ             NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_licitacion_numero_expediente  ON licitacion (numero_expediente);
CREATE INDEX idx_licitacion_estado             ON licitacion (estado);
CREATE INDEX idx_licitacion_fecha              ON licitacion (fecha);
CREATE INDEX idx_licitacion_owner_id           ON licitacion (owner_id);
CREATE INDEX idx_licitacion_organismo_id       ON licitacion (organismo_id);
CREATE INDEX idx_licitacion_area_tecnologica   ON licitacion (area_tecnologica_id);

CREATE TABLE adjudicacion (
  id                               BIGSERIAL               PRIMARY KEY,

  licitacion_id                    BIGINT                  REFERENCES licitacion(id),

  fecha_alerta                     DATE,
  fecha_adjudicacion               DATE,
  titulo                           TEXT                    NOT NULL,
  numero_expediente                TEXT                    NOT NULL,
  control_expediente               SMALLINT,

  importe                          NUMERIC(15, 2),
  ratio_adjudicacion_vs_licitacion NUMERIC(7, 4),

  area_tecnologica_id              INT                     REFERENCES area_tecnologica(id),
  es_area_interes                  BOOLEAN,

  ambito_geografico                ambito_geografico_tipo,
  comunidad_autonoma               comunidad_autonoma_tipo,
  provincia                        TEXT,

  organismo_id                     INT                     REFERENCES organismo(id),
  adjudicatario_id                 INT                     REFERENCES adjudicatario(id),

  mercado_vertical                 mercado_vertical_tipo,
  competencia                      TEXT,
  tipo_procedimiento               tipo_procedimiento_tipo,

  duracion_meses                   SMALLINT,
  prorrogas_meses                  SMALLINT,

  puntos_precio                    SMALLINT    CHECK (puntos_precio BETWEEN 0 AND 100),
  puntos_mejoras                   SMALLINT    CHECK (puntos_mejoras BETWEEN 0 AND 100),
  puntos_subjetivos                SMALLINT    CHECK (puntos_subjetivos BETWEEN 0 AND 100),

  created_at                       TIMESTAMPTZ             NOT NULL DEFAULT NOW(),
  updated_at                       TIMESTAMPTZ             NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_adjudicacion_numero_expediente  ON adjudicacion (numero_expediente);
CREATE INDEX idx_adjudicacion_licitacion_id      ON adjudicacion (licitacion_id);
CREATE INDEX idx_adjudicacion_fecha              ON adjudicacion (fecha_adjudicacion);
CREATE INDEX idx_adjudicacion_adjudicatario_id   ON adjudicacion (adjudicatario_id);
CREATE INDEX idx_adjudicacion_area_tecnologica   ON adjudicacion (area_tecnologica_id);

-- ── Junction / Child Tables ──────────────────────────────────

CREATE TABLE licitacion_cpv (
  licitacion_id   BIGINT      NOT NULL REFERENCES licitacion(id)  ON DELETE CASCADE,
  cpv_code        VARCHAR(8)  NOT NULL REFERENCES cpv_code(code),
  PRIMARY KEY (licitacion_id, cpv_code)
);

CREATE TABLE adjudicacion_cpv (
  adjudicacion_id BIGINT      NOT NULL REFERENCES adjudicacion(id) ON DELETE CASCADE,
  cpv_code        VARCHAR(8)  NOT NULL REFERENCES cpv_code(code),
  PRIMARY KEY (adjudicacion_id, cpv_code)
);

CREATE TABLE licitacion_proveedor_contactado (
  licitacion_id   BIGINT  NOT NULL REFERENCES licitacion(id) ON DELETE CASCADE,
  proveedor_id    INT     NOT NULL REFERENCES proveedor_interno(id),
  PRIMARY KEY (licitacion_id, proveedor_id)
);

CREATE TABLE licitacion_cotizacion (
  id                SERIAL      PRIMARY KEY,
  licitacion_id     BIGINT      NOT NULL REFERENCES licitacion(id) ON DELETE CASCADE,
  orden             SMALLINT    NOT NULL CHECK (orden BETWEEN 1 AND 10),
  cliente_nombre    TEXT        NOT NULL,
  estado_cotizacion TEXT,
  UNIQUE (licitacion_id, orden)
);

-- ── Seed Data ────────────────────────────────────────────────

INSERT INTO proveedor_interno (nombre) VALUES
  ('CONFIGURACIONES INGRAM'),
  ('ZELENZIA'),
  ('OXIONA'),
  ('SOLUTIA'),
  ('PLEXUS'),
  ('SEMIC'),
  ('HUB-TECH'),
  ('ATTENTO'),
  ('EMESA'),
  ('ADER'),
  ('UPPERSOLUTIONS'),
  ('DREAMOPTION');
