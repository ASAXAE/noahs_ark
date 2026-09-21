require('dotenv').config();

const {
    after,
    test,
} = require('node:test');
const assert = require('node:assert/strict');
const bcrypt = require('bcryptjs');
const crypto = require('node:crypto');

const pool = require('../src/database');

const {
    issuePasswordResetToken,
    resetPasswordWithToken,
} = require('../src/password_reset');

const {
    issueRefreshToken,
    rotateRefreshToken,
} = require('../src/refresh_token');

const originalPassword = 'OriginalPassword123';
const previousTokenLifetime =
    process.env.PASSWORD_RESET_TOKEN_TTL_MINUTES;

process.env.PASSWORD_RESET_TOKEN_TTL_MINUTES = '60';

after(async () => {
    if (previousTokenLifetime === undefined) {
        delete process.env.PASSWORD_RESET_TOKEN_TTL_MINUTES;
    } else {
        process.env.PASSWORD_RESET_TOKEN_TTL_MINUTES =
            previousTokenLifetime;
    }

    await pool.end();
});

function hashToken(rawToken) {
    return crypto
        .createHash('sha256')
        .update(rawToken)
        .digest('hex');
}

async function createTestUser(label) {
    const uniqueValue =
        `${Date.now()}-${crypto.randomUUID()}`;

    const email =
        `password-reset-${label}-${uniqueValue}@example.com`;

    const passwordHash = await bcrypt.hash(
        originalPassword,
        12,
    );

    const result = await pool.query(
        `
            INSERT INTO users (
                display_name,
                email,
                password_hash
            )
            VALUES ($1, $2, $3)
            RETURNING id
        `,
        [
            `Password Reset ${label}`,
            email,
            passwordHash,
        ],
    );

    return {
        id: result.rows[0].id,
        passwordHash,
    };
}

async function deleteTestUser(userId) {
    if (userId === undefined) {
        return;
    }

    await pool.query(
        `
            DELETE FROM users
            WHERE id = $1
        `,
        [userId],
    );
}

test('issues a random token while storing only its hash', async () => {
    let userId;

    try {
        const user = await createTestUser('issuance');
        userId = user.id;

        const rawToken = await issuePasswordResetToken(
            pool,
            userId,
        );

        assert.match(rawToken, /^[0-9a-f]{64}$/);

        const result = await pool.query(
            `
                SELECT
                    token_hash AS "tokenHash",
                    EXTRACT(
                        EPOCH FROM expires_at - created_at
                    )::DOUBLE PRECISION AS "lifetimeSeconds"
                FROM password_reset_tokens
                WHERE user_id = $1
            `,
            [userId],
        );

        assert.equal(result.rowCount, 1);
        assert.equal(
            result.rows[0].tokenHash,
            hashToken(rawToken),
        );
        assert.notEqual(
            result.rows[0].tokenHash,
            rawToken,
        );

        assert.ok(
            result.rows[0].lifetimeSeconds >= 3599 &&
                result.rows[0].lifetimeSeconds <= 3605,
        );
    } finally {
        await deleteTestUser(userId);
    }
});

test('resets the password and revokes all existing sessions', async () => {
    let userId;

    try {
        const user = await createTestUser('success');
        userId = user.id;

        const firstRefreshSession =
            await issueRefreshToken(pool, userId);

        const secondRefreshSession =
            await issueRefreshToken(pool, userId);

        const usedResetToken =
            await issuePasswordResetToken(pool, userId);

        const siblingResetToken =
            await issuePasswordResetToken(pool, userId);

        const newPassword = 'ReplacementPassword456';
        const newPasswordHash = await bcrypt.hash(
            newPassword,
            12,
        );

        assert.equal(
            await resetPasswordWithToken(
                pool,
                usedResetToken,
                newPasswordHash,
            ),
            true,
        );

        const userResult = await pool.query(
            `
                SELECT password_hash AS "passwordHash"
                FROM users
                WHERE id = $1
            `,
            [userId],
        );

        assert.equal(
            await bcrypt.compare(
                newPassword,
                userResult.rows[0].passwordHash,
            ),
            true,
        );

        assert.equal(
            await bcrypt.compare(
                originalPassword,
                userResult.rows[0].passwordHash,
            ),
            false,
        );

        const resetTokenResult = await pool.query(
            `
                SELECT
                    COUNT(*)::INTEGER AS token_count,
                    COUNT(*) FILTER (
                        WHERE consumed_at IS NOT NULL
                    )::INTEGER AS consumed_count
                FROM password_reset_tokens
                WHERE user_id = $1
            `,
            [userId],
        );

        assert.equal(
            resetTokenResult.rows[0].token_count,
            2,
        );
        assert.equal(
            resetTokenResult.rows[0].consumed_count,
            2,
        );

        const refreshTokenResult = await pool.query(
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
            refreshTokenResult.rows[0].token_count,
            2,
        );
        assert.equal(
            refreshTokenResult.rows[0].revoked_count,
            2,
        );

        assert.equal(
            (
                await rotateRefreshToken(
                    pool,
                    firstRefreshSession.refreshToken,
                )
            ).status,
            'invalid',
        );

        assert.equal(
            (
                await rotateRefreshToken(
                    pool,
                    secondRefreshSession.refreshToken,
                )
            ).status,
            'invalid',
        );

        assert.equal(
            await resetPasswordWithToken(
                pool,
                usedResetToken,
                newPasswordHash,
            ),
            false,
        );

        assert.equal(
            await resetPasswordWithToken(
                pool,
                siblingResetToken,
                newPasswordHash,
            ),
            false,
        );
    } finally {
        await deleteTestUser(userId);
    }
});

test('rejects expired and malformed reset tokens', async () => {
    let userId;

    try {
        const user = await createTestUser('expiration');
        userId = user.id;

        const rawToken = await issuePasswordResetToken(
            pool,
            userId,
        );

        await pool.query(
            `
                UPDATE password_reset_tokens
                SET
                    created_at =
                        clock_timestamp() - INTERVAL '2 hours',
                    expires_at =
                        clock_timestamp() - INTERVAL '1 hour'
                WHERE token_hash = $1
            `,
            [hashToken(rawToken)],
        );

        const replacementHash = await bcrypt.hash(
            'ExpiredReplacement789',
            12,
        );

        assert.equal(
            await resetPasswordWithToken(
                pool,
                rawToken,
                replacementHash,
            ),
            false,
        );

        assert.equal(
            await resetPasswordWithToken(
                pool,
                'not-a-valid-token',
                replacementHash,
            ),
            false,
        );

        const userResult = await pool.query(
            `
                SELECT password_hash AS "passwordHash"
                FROM users
                WHERE id = $1
            `,
            [userId],
        );

        assert.equal(
            userResult.rows[0].passwordHash,
            user.passwordHash,
        );
    } finally {
        await deleteTestUser(userId);
    }
});

test('allows only one concurrent reset with the same token', async () => {
    let userId;

    try {
        const user = await createTestUser('concurrency');
        userId = user.id;

        const rawToken = await issuePasswordResetToken(
            pool,
            userId,
        );

        const firstPassword = 'ConcurrentPassword111';
        const secondPassword = 'ConcurrentPassword222';

        const firstHash = await bcrypt.hash(
            firstPassword,
            12,
        );
        const secondHash = await bcrypt.hash(
            secondPassword,
            12,
        );

        const results = await Promise.all([
            resetPasswordWithToken(
                pool,
                rawToken,
                firstHash,
            ),
            resetPasswordWithToken(
                pool,
                rawToken,
                secondHash,
            ),
        ]);

        assert.deepEqual(
            [...results].sort(),
            [false, true],
        );

        const userResult = await pool.query(
            `
                SELECT password_hash AS "passwordHash"
                FROM users
                WHERE id = $1
            `,
            [userId],
        );

        const passwordMatches = await Promise.all([
            bcrypt.compare(
                firstPassword,
                userResult.rows[0].passwordHash,
            ),
            bcrypt.compare(
                secondPassword,
                userResult.rows[0].passwordHash,
            ),
        ]);

        assert.equal(
            passwordMatches.filter(Boolean).length,
            1,
        );
    } finally {
        await deleteTestUser(userId);
    }
});