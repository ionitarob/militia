CREATE TABLE registration_request (
    id              BIGSERIAL PRIMARY KEY,
    email           TEXT        NOT NULL,
    nombre          TEXT        NOT NULL,
    password_hash   TEXT        NOT NULL,
    role            TEXT        NOT NULL DEFAULT 'ventas',
    otp_code        TEXT        NOT NULL,
    otp_expires_at  TIMESTAMPTZ NOT NULL,
    otp_verified    BOOLEAN     NOT NULL DEFAULT FALSE,
    status          TEXT        NOT NULL DEFAULT 'pending_otp',
    approved_by     INT         REFERENCES app_user(id),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX ON registration_request (email);
CREATE INDEX ON registration_request (status);
