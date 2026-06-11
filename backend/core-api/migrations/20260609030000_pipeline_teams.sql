-- ============================================================
-- IMLiti – Migration 004: Sales Pipeline & Teams
-- ============================================================

-- ── 1. Internal pipeline stage (distinct from portal estado) ──
CREATE TYPE pipeline_stage AS ENUM (
    'nueva',
    'asignada',
    'en_proceso',
    'cotizaciones_enviadas',
    'presentada',
    'ganada',
    'perdida',
    'desierta'
);

ALTER TABLE licitacion
    ADD COLUMN pipeline_stage pipeline_stage NOT NULL DEFAULT 'nueva';

CREATE INDEX idx_licitacion_pipeline ON licitacion (pipeline_stage);

-- ── 2. Teams (flexible many-to-many: admin ↔ vendedor) ────────
CREATE TABLE team (
    id          SERIAL      PRIMARY KEY,
    nombre      TEXT        NOT NULL,
    created_by  INTEGER     NOT NULL REFERENCES app_user(id),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE team_member (
    team_id  INTEGER     NOT NULL REFERENCES team(id) ON DELETE CASCADE,
    user_id  INTEGER     NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
    added_by INTEGER     NOT NULL REFERENCES app_user(id),
    added_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (team_id, user_id)
);

-- ── 3. Assignment (one active assignee per licitacion) ─────────
CREATE TABLE licitacion_assignment (
    id            SERIAL      PRIMARY KEY,
    licitacion_id BIGINT      NOT NULL REFERENCES licitacion(id) ON DELETE CASCADE,
    assignee_id   INTEGER     NOT NULL REFERENCES app_user(id),
    assigned_by   INTEGER     NOT NULL REFERENCES app_user(id),
    assigned_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    is_force      BOOLEAN     NOT NULL DEFAULT FALSE,
    active        BOOLEAN     NOT NULL DEFAULT TRUE
);

CREATE INDEX idx_assignment_licitacion ON licitacion_assignment (licitacion_id) WHERE active = TRUE;
CREATE INDEX idx_assignment_assignee   ON licitacion_assignment (assignee_id)   WHERE active = TRUE;

-- ── 4. Decline log (vendedor refuses → admin resolves) ─────────
CREATE TABLE licitacion_decline (
    id            SERIAL      PRIMARY KEY,
    licitacion_id BIGINT      NOT NULL REFERENCES licitacion(id) ON DELETE CASCADE,
    user_id       INTEGER     NOT NULL REFERENCES app_user(id),
    reason        TEXT,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    resolved      BOOLEAN     NOT NULL DEFAULT FALSE,
    resolved_by   INTEGER     REFERENCES app_user(id),
    resolved_at   TIMESTAMPTZ
);

CREATE INDEX idx_decline_unresolved ON licitacion_decline (licitacion_id) WHERE resolved = FALSE;

-- ── 5. Quote log (structured client/reseller tracking) ─────────
CREATE TYPE quote_status AS ENUM ('pendiente', 'aprobada', 'rechazada');

CREATE TABLE licitacion_quote (
    id            SERIAL       PRIMARY KEY,
    licitacion_id BIGINT       NOT NULL REFERENCES licitacion(id) ON DELETE CASCADE,
    vendedor_id   INTEGER      NOT NULL REFERENCES app_user(id),
    reseller_name TEXT         NOT NULL,
    date_sent     DATE,
    amount        NUMERIC(15,2),
    status        quote_status NOT NULL DEFAULT 'pendiente',
    notes         TEXT,
    created_at    TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at    TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_quote_licitacion ON licitacion_quote (licitacion_id);

-- ── 6. Notes / activity thread ─────────────────────────────────
CREATE TABLE licitacion_note (
    id            SERIAL      PRIMARY KEY,
    licitacion_id BIGINT      NOT NULL REFERENCES licitacion(id) ON DELETE CASCADE,
    user_id       INTEGER     NOT NULL REFERENCES app_user(id),
    content       TEXT        NOT NULL,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_note_licitacion ON licitacion_note (licitacion_id);
