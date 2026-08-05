CREATE TABLE IF NOT EXISTS thoughts (
    id BIGSERIAL PRIMARY KEY,

    user_id BIGINT NOT NULL
        REFERENCES users(id)
        ON DELETE CASCADE,

    title VARCHAR(50) NOT NULL DEFAULT '',
    content TEXT NOT NULL,
    tag VARCHAR(20) NOT NULL,

    is_favorite BOOLEAN NOT NULL DEFAULT FALSE,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_thoughts_user_created_at
ON thoughts(user_id, created_at DESC);