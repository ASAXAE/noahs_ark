require('dotenv').config();

const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const { after, test } = require('node:test');

const pool = require('../src/database');

const {
    issueRefreshToken,
    rotateRefreshToken,
    revokeRefreshToken,
} = require('../src/refresh_token');

process.env.REFRESH_TOKEN_TTL_DAYS = '30';

after(async () => {
    await pool.end();
});

function hashToken(rawToken) {
    return crypto
        .createHash('sha256')
        .update(rawToken)
        .digest('hex');
}

async function createTestUser(label) {
    const email =
        `refresh-${label}-${crypto.randomUUID()}@example.com`;

    const result = await pool.query(
        `
            INSERT INTO users (
                display_name,
                email
            )
            VALUES ($1, $2)
            RETURNING id
        `,
        [
            `Refresh ${label}`,
            email,
        ],
    );

    return result.rows[0].id;
}

async function deleteTestUser(userId) {
    if (userId === undefined) {
        return;
    }

    await pool.query(
        'DELETE FROM users WHERE id = $1',
        [userId],
    );
}

test('issues a 30-day token and stores only its hash', async () => {
    let userId;

    try {
        userId = await createTestUser('issue');

        const issued = await issueRefreshToken(
            pool,
            userId,
        );

        assert.match(
            issued.refreshToken,
            /^[0-9a-f]{64}$/,
        );

        const result = await pool.query(
            `
                SELECT
                    family_id,
                    token_hash,
                    expires_at,
                    rotated_at,
                    revoked_at,
                    expires_at >
                        clock_timestamp()
                        + INTERVAL '29 days 23 hours'
                        AS "hasMinimumLifetime",
                    expires_at <=
                        clock_timestamp()
                        + INTERVAL '30 days'
                        AS "hasMaximumLifetime"
                FROM refresh_tokens
                WHERE user_id = $1
            `,
            [userId],
        );

        assert.equal(result.rowCount, 1);

        const storedToken = result.rows[0];
        const expectedHash =
            hashToken(issued.refreshToken);

        assert.equal(
            storedToken.token_hash,
            expectedHash,
        );

        assert.notEqual(
            storedToken.token_hash,
            issued.refreshToken,
        );

        assert.match(
            storedToken.family_id,
            /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/,
        );

        assert.equal(
            storedToken.rotated_at,
            null,
        );

        assert.equal(
            storedToken.revoked_at,
            null,
        );

        assert.equal(
            storedToken.hasMinimumLifetime,
            true,
        );

        assert.equal(
            storedToken.hasMaximumLifetime,
            true,
        );

        assert.equal(
            storedToken.expires_at.getTime(),
            issued.expiresAt.getTime(),
        );
    } finally {
        await deleteTestUser(userId);
    }
});

test('rotates a token without extending its family lifetime', async () => {
    let userId;

    try {
        userId = await createTestUser('rotation');

        const issued = await issueRefreshToken(
            pool,
            userId,
        );

        const rotated = await rotateRefreshToken(
            pool,
            issued.refreshToken,
        );

        assert.equal(
            rotated.status,
            'rotated',
        );

        assert.notEqual(
            rotated.refreshToken,
            issued.refreshToken,
        );

        assert.equal(
            String(rotated.userId),
            String(userId),
        );

        const result = await pool.query(
            `
                SELECT
                    id,
                    family_id,
                    token_hash,
                    expires_at,
                    rotated_at,
                    revoked_at,
                    replaced_by_token_id
                FROM refresh_tokens
                WHERE user_id = $1
                ORDER BY id
            `,
            [userId],
        );

        assert.equal(result.rowCount, 2);

        const original = result.rows[0];
        const replacement = result.rows[1];

        assert.equal(
            original.family_id,
            replacement.family_id,
        );

        assert.equal(
            original.expires_at.getTime(),
            replacement.expires_at.getTime(),
        );

        assert.equal(
            original.token_hash,
            hashToken(issued.refreshToken),
        );

        assert.equal(
            replacement.token_hash,
            hashToken(rotated.refreshToken),
        );

        assert.notEqual(
            original.rotated_at,
            null,
        );

        assert.equal(
            String(original.replaced_by_token_id),
            String(replacement.id),
        );

        assert.equal(
            replacement.rotated_at,
            null,
        );

        assert.equal(
            replacement.revoked_at,
            null,
        );
    } finally {
        await deleteTestUser(userId);
    }
});

test('detects reuse and revokes the entire token family', async () => {
    let userId;

    try {
        userId = await createTestUser('reuse');

        const issued = await issueRefreshToken(
            pool,
            userId,
        );

        const rotated = await rotateRefreshToken(
            pool,
            issued.refreshToken,
        );

        assert.equal(rotated.status, 'rotated');

        const reused = await rotateRefreshToken(
            pool,
            issued.refreshToken,
        );

        assert.equal(reused.status, 'reused');

        const stateResult = await pool.query(
            `
                SELECT
                    COUNT(*)::INTEGER AS token_count,
                    COUNT(*) FILTER (
                        WHERE revoked_at IS NOT NULL
                    )::INTEGER AS revoked_count
                FROM refresh_tokens
                WHERE user_id = $1
            `,
            [userId],
        );

        assert.equal(
            stateResult.rows[0].token_count,
            2,
        );

        assert.equal(
            stateResult.rows[0].revoked_count,
            2,
        );

        const replacementAttempt =
            await rotateRefreshToken(
                pool,
                rotated.refreshToken,
            );

        assert.equal(
            replacementAttempt.status,
            'invalid',
        );
    } finally {
        await deleteTestUser(userId);
    }
});

test('serializes concurrent rotation attempts', async () => {
    let userId;

    try {
        userId = await createTestUser('concurrent');

        const issued = await issueRefreshToken(
            pool,
            userId,
        );

        const results = await Promise.all([
            rotateRefreshToken(
                pool,
                issued.refreshToken,
            ),
            rotateRefreshToken(
                pool,
                issued.refreshToken,
            ),
        ]);

        assert.deepEqual(
            results
                .map((result) => result.status)
                .sort(),
            ['reused', 'rotated'],
        );

        const stateResult = await pool.query(
            `
                SELECT
                    COUNT(*)::INTEGER AS token_count,
                    COUNT(*) FILTER (
                        WHERE revoked_at IS NOT NULL
                    )::INTEGER AS revoked_count
                FROM refresh_tokens
                WHERE user_id = $1
            `,
            [userId],
        );

        assert.equal(
            stateResult.rows[0].token_count,
            2,
        );

        assert.equal(
            stateResult.rows[0].revoked_count,
            2,
        );
    } finally {
        await deleteTestUser(userId);
    }
});

test('revokes a family and rejects expired tokens', async () => {
    let revokedUserId;
    let expiredUserId;

    try {
        revokedUserId =
            await createTestUser('revocation');

        const issued = await issueRefreshToken(
            pool,
            revokedUserId,
        );

        const rotated = await rotateRefreshToken(
            pool,
            issued.refreshToken,
        );

        assert.equal(rotated.status, 'rotated');

        assert.equal(
            await revokeRefreshToken(
                pool,
                rotated.refreshToken,
            ),
            true,
        );

        const revokedResult = await pool.query(
            `
                SELECT
                    COUNT(*)::INTEGER AS token_count,
                    COUNT(*) FILTER (
                        WHERE revoked_at IS NOT NULL
                    )::INTEGER AS revoked_count
                FROM refresh_tokens
                WHERE user_id = $1
            `,
            [revokedUserId],
        );

        assert.equal(
            revokedResult.rows[0].token_count,
            2,
        );

        assert.equal(
            revokedResult.rows[0].revoked_count,
            2,
        );

        assert.equal(
            (
                await rotateRefreshToken(
                    pool,
                    rotated.refreshToken,
                )
            ).status,
            'invalid',
        );

        expiredUserId =
            await createTestUser('expiration');

        const expired = await issueRefreshToken(
            pool,
            expiredUserId,
        );

        await pool.query(
            `
                UPDATE refresh_tokens
                SET
                    created_at =
                        clock_timestamp()
                        - INTERVAL '31 days',
                    expires_at =
                        clock_timestamp()
                        - INTERVAL '1 day'
                WHERE token_hash = $1
            `,
            [hashToken(expired.refreshToken)],
        );

        assert.equal(
            (
                await rotateRefreshToken(
                    pool,
                    expired.refreshToken,
                )
            ).status,
            'invalid',
        );

        assert.equal(
            await revokeRefreshToken(
                pool,
                'invalid-token',
            ),
            false,
        );
    } finally {
        await deleteTestUser(revokedUserId);
        await deleteTestUser(expiredUserId);
    }
});
