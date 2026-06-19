CREATE TABLE chat_session (
    id         UUID    PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id    INT     NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_chat_session_user ON chat_session(user_id);

CREATE TABLE chat_message (
    id         BIGSERIAL PRIMARY KEY,
    session_id UUID  NOT NULL REFERENCES chat_session(id) ON DELETE CASCADE,
    role       TEXT  NOT NULL CHECK (role IN ('user', 'assistant')),
    content    TEXT  NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_chat_message_session ON chat_message(session_id, created_at);
