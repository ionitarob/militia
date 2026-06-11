CREATE TYPE user_role AS ENUM ('admin', 'ventas');

CREATE TABLE app_user (
    id           SERIAL PRIMARY KEY,
    email        TEXT UNIQUE NOT NULL,
    password_hash TEXT NOT NULL,
    role         user_role NOT NULL DEFAULT 'ventas',
    nombre       TEXT,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_login   TIMESTAMPTZ
);

-- Seed one admin so the system is not empty on first deploy.
-- Password: Admin2025! (bcrypt, cost 12) — CHANGE after first login.
INSERT INTO app_user (email, password_hash, role, nombre)
VALUES (
    'admin@imliti.com',
    '$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TiGqeFaI0N7pCJPiC5bOTsmMUBFu',
    'admin',
    'Administrador'
);
