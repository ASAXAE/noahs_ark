require('dotenv').config();

const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const { after, test } = require('node:test');

const pool = require('../src/database');
const {
    issueEmailVerificationToken,
    consumeEmailVerificationToken,
} = require('../src/email_verification');

after(async () => {
    await pool.end();
});

test('stores a token hash and consumes the token only once', async () => {
    const email = `verify-${crypto.randomUUID()}@example.com`;
    let userId;

    try {
        const userResult = await pool.query(
            `
                INSERT INTO users (display_name, email)
                VALUES ($1, $2)
                RETURNING id
            `,
            ['Verification Test', email],
        );
        userId = userResult.rows[0].id;

        const rawToken = await issueEmailVerificationToken(pool, userId);
        assert.match(rawToken, /^[0-9a-f]{64}$/);

        const tokenResult = await pool.query(
            `
                SELECT
                    token_hash,
                    consumed_at,
                    expires_at > NOW() AS is_unexpired
                FROM email_verification_tokens
                WHERE user_id = $1
            `,
            [userId],
        );

        assert.equal(tokenResult.rows.length, 1);

        const storedToken = tokenResult.rows[0];
        const expectedHash = crypto
            .createHash('sha256')
            .update(rawToken)
            .digest('hex');

        assert.equal(storedToken.token_hash, expectedHash);
        assert.notEqual(storedToken.token_hash, rawToken);
        assert.equal(storedToken.consumed_at, null);
        assert.equal(storedToken.is_unexpired, true);

        assert.equal(
            await consumeEmailVerificationToken(pool, rawToken),
            true,
        );

        const verifiedResult = await pool.query(
            `
                SELECT
                    users.email_verified_at,
                    tokens.consumed_at
                FROM users
                JOIN email_verification_tokens AS tokens
                    ON tokens.user_id = users.id
                WHERE users.id = $1
            `,
            [userId],
        );

        assert.notEqual(verifiedResult.rows[0].email_verified_at, null);
        assert.notEqual(verifiedResult.rows[0].consumed_at, null);

        assert.equal(
            await consumeEmailVerificationToken(pool, rawToken),
            false,
        );
    } finally {
        if (userId !== undefined) {
            await pool.query(
                'DELETE FROM users WHERE id = $1',
                [userId],
            );
        }
    }
});
test('rejects an expired token without verifying the user', async () => {
    const email = `verify-expired-${crypto.randomUUID()}@example.com`;
    let userId;

    try {
        const userResult = await pool.query(
            `
                INSERT INTO users (display_name, email)
                VALUES ($1, $2)
                RETURNING id
            `,
            ['Expired Token Test', email],
        );
        userId = userResult.rows[0].id;

        const rawToken = await issueEmailVerificationToken(pool, userId);

        const expireResult = await pool.query(
            `
                UPDATE email_verification_tokens
                SET created_at = NOW() - INTERVAL '2 days',
                    expires_at = NOW() - INTERVAL '1 day'
                WHERE user_id = $1
            `,
            [userId],
        );
        assert.equal(expireResult.rowCount, 1);

        assert.equal(
            await consumeEmailVerificationToken(pool, rawToken),
            false,
        );

        const stateResult = await pool.query(
            `
                SELECT
                    users.email_verified_at,
                    tokens.consumed_at
                FROM users
                JOIN email_verification_tokens AS tokens
                    ON tokens.user_id = users.id
                WHERE users.id = $1
            `,
            [userId],
        );

        assert.equal(stateResult.rows[0].email_verified_at, null);
        assert.equal(stateResult.rows[0].consumed_at, null);
    } finally {
        if (userId !== undefined) {
            await pool.query(
                'DELETE FROM users WHERE id = $1',
                [userId],
            );
        }
    }
});

test('concurrent attempts consume a token only once', async () => {
    const email = `verify-concurrent-${crypto.randomUUID()}@example.com`;
    let userId;

    try {
        const userResult = await pool.query(
            `
                INSERT INTO users (display_name, email)
                VALUES ($1, $2)
                RETURNING id
            `,
            ['Concurrent Token Test', email],
        );
        userId = userResult.rows[0].id;

        const rawToken = await issueEmailVerificationToken(pool, userId);
        const results = await Promise.all([
            consumeEmailVerificationToken(pool, rawToken),
            consumeEmailVerificationToken(pool, rawToken),
        ]);

        assert.equal(results.filter((value) => value === true).length, 1);
        assert.equal(results.filter((value) => value === false).length, 1);
    } finally {
        if (userId !== undefined) {
            await pool.query(
                'DELETE FROM users WHERE id = $1',
                [userId],
            );
        }
    }
});
