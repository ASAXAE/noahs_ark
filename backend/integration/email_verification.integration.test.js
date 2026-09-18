require('dotenv').config();

const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const { after, test } = require('node:test');

const pool = require('../src/database');
const {
    issueEmailVerificationToken,
    consumeEmailVerificationToken,
} = require('../src/email_verification');

const {
    issueRateLimitedVerificationToken,
} = require('../src/verification_request');

const {
    createFakeVerificationMailer,
} = require('../src/verification_mailer');
const {
    requestVerificationEmail,
} = require('../src/verification_delivery');

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

test('limits concurrent verification requests for one account', async () => {
    const email = `verify-limit-${crypto.randomUUID()}@example.com`;
    let userId;

    try {
        const userResult = await pool.query(
            `
                INSERT INTO users (display_name, email)
                VALUES ($1, $2)
                RETURNING id
            `,
            ['Rate Limit Test', email],
        );
        userId = userResult.rows[0].id;

        const attempts = await Promise.all([
            issueRateLimitedVerificationToken(pool, userId),
            issueRateLimitedVerificationToken(pool, userId),
        ]);

        assert.deepEqual(
            attempts.map((attempt) => attempt.status).sort(),
            ['issued', 'rate_limited'],
        );

        const issued = attempts.find(
            (attempt) => attempt.status === 'issued',
        );
        assert.equal(issued.to, email);
        assert.match(issued.token, /^[0-9a-f]{64}$/);

        const tokenResult = await pool.query(
            `
                SELECT COUNT(*)::INTEGER AS token_count
                FROM email_verification_tokens
                WHERE user_id = $1
            `,
            [userId],
        );
        assert.equal(tokenResult.rows[0].token_count, 1);
    } finally {
        if (userId !== undefined) {
            await pool.query(
                'DELETE FROM users WHERE id = $1',
                [userId],
            );
        }
    }
});

test('delivers a verification token to the fake mailer', async () => {
    const email = `verify-send-${crypto.randomUUID()}@example.com`;
    let userId;

    try {
        const userResult = await pool.query(
            `
                INSERT INTO users (display_name, email)
                VALUES ($1, $2)
                RETURNING id
            `,
            ['Delivery Test', email],
        );
        userId = userResult.rows[0].id;

        const mailer = createFakeVerificationMailer();
        const result = await requestVerificationEmail(
            pool,
            userId,
            mailer,
        );

        assert.deepEqual(result, { status: 'sent' });
        assert.equal(mailer.sentMessages.length, 1);

        const { to, token } = mailer.sentMessages[0];
        assert.equal(to, email);
        assert.match(token, /^[0-9a-f]{64}$/);

        const stored = await pool.query(
            `
                SELECT token_hash
                FROM email_verification_tokens
                WHERE user_id = $1
            `,
            [userId],
        );
        assert.equal(stored.rows.length, 1);
        assert.equal(
            stored.rows[0].token_hash,
            crypto.createHash('sha256').update(token).digest('hex'),
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

test('removes the token when verification delivery fails', async () => {
    const email = `verify-fail-${crypto.randomUUID()}@example.com`;
    let userId;

    try {
        const userResult = await pool.query(
            `
                INSERT INTO users (display_name, email)
                VALUES ($1, $2)
                RETURNING id
            `,
            ['Failed Delivery Test', email],
        );
        userId = userResult.rows[0].id;

        const failingMailer = {
            async sendVerificationEmail() {
                throw new Error('fake delivery failure');
            },
        };

        await assert.rejects(
            requestVerificationEmail(pool, userId, failingMailer),
            /fake delivery failure/,
        );

        const tokenResult = await pool.query(
            `
                SELECT COUNT(*)::INTEGER AS token_count
                FROM email_verification_tokens
                WHERE user_id = $1
            `,
            [userId],
        );
        assert.equal(tokenResult.rows[0].token_count, 0);

        const retryMailer = createFakeVerificationMailer();
        const retry = await requestVerificationEmail(
            pool,
            userId,
            retryMailer,
        );
        assert.deepEqual(retry, { status: 'sent' });
        assert.equal(retryMailer.sentMessages.length, 1);
    } finally {
        if (userId !== undefined) {
            await pool.query(
                'DELETE FROM users WHERE id = $1',
                [userId],
            );
        }
    }
});

test('limits verification requests to five per 24 hours', async () => {
    const email = `verify-daily-${crypto.randomUUID()}@example.com`;
    let userId;

    try {
        const userResult = await pool.query(
            `
                INSERT INTO users (display_name, email)
                VALUES ($1, $2)
                RETURNING id
            `,
            ['Daily Limit Test', email],
        );
        userId = userResult.rows[0].id;

        for (let attempt = 0; attempt < 5; attempt += 1) {
            const issued = await issueRateLimitedVerificationToken(
                pool,
                userId,
            );
            assert.equal(issued.status, 'issued');

            await pool.query(
                `
                    UPDATE email_verification_tokens
                    SET created_at =
                        clock_timestamp() - INTERVAL '2 minutes'
                    WHERE user_id = $1
                `,
                [userId],
            );
        }

        const blocked = await issueRateLimitedVerificationToken(
            pool,
            userId,
        );
        assert.equal(blocked.status, 'rate_limited');

        await pool.query(
            `
                UPDATE email_verification_tokens
                SET created_at =
                        clock_timestamp() - INTERVAL '25 hours',
                    expires_at =
                        clock_timestamp() - INTERVAL '1 hour'
                WHERE user_id = $1
            `,
            [userId],
        );

        const afterWindow = await issueRateLimitedVerificationToken(
            pool,
            userId,
        );
        assert.equal(afterWindow.status, 'issued');
    } finally {
        if (userId !== undefined) {
            await pool.query(
                'DELETE FROM users WHERE id = $1',
                [userId],
            );
        }
    }
});