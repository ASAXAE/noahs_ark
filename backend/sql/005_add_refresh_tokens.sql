CREATE TABLE IF NOT EXISTS refresh_tokens (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    family_id UUID NOT NULL,
    token_hash VARCHAR(64) NOT NULL UNIQUE
        CHECK (token_hash ~ '^[0-9a-f]{64}$'),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at TIMESTAMPTZ NOT NULL,
    rotated_at TIMESTAMPTZ,
    revoked_at TIMESTAMPTZ,
    replaced_by_token_id BIGINT
        REFERENCES refresh_tokens(id)
        ON DELETE SET NULL,
    CONSTRAINT refresh_tokens_expiry
        CHECK (expires_at > created_at),
    CONSTRAINT refresh_tokens_replacement_requires_rotation
        CHECK (
            replaced_by_token_id IS NULL
            OR rotated_at IS NOT NULL
        ),
    CONSTRAINT refresh_tokens_cannot_replace_self
        CHECK (
            replaced_by_token_id IS NULL
            OR replaced_by_token_id <> id
        )
);

CREATE INDEX IF NOT EXISTS idx_refresh_tokens_user_id
ON refresh_tokens (user_id);

CREATE INDEX IF NOT EXISTS idx_refresh_tokens_family_id
ON refresh_tokens (family_id);
