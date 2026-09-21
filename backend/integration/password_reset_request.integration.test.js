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
    createFakePasswordResetMailer,
} = require('../src/password_reset_mailer');

const {
    requestPasswordResetEmail,
} = require('../src/password_reset_delivery');

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
    const uniqueValue =
        `${Date.now()}-${crypto.randomUUID()}`;

    const email =
        `reset-request-${label}-${uniqueValue}@example.com`;

    const passwordHash = await bcrypt.hash(
        'OriginalPassword123',
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
            RETURNING id, email
        `,
        [
            `Reset Request ${label}`,
            email,
            passwordHash,
        ],
    );

    return result.rows[0];
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

test('normalizes email and stores only the token hash', async () => {
    let userId;

    try {
        const user = await createTestUser('delivery');
        userId = user.id;

        const mailer = createFakePasswordResetMailer();

        const result = await requestPasswordResetEmail(
            pool,
            `  ${user.email.toUpperCase()}  `,
            mailer,
        );

        assert.deepEqual(result, {
            status: 'accepted',
        });

        assert.equal(mailer.sentMessages.length, 1);
        assert.equal(
            mailer.sentMessages[0].to,
            user.email,
        );

        const rawToken =
            mailer.sentMessages[0].token;

        assert.match(rawToken, /^[0-9a-f]{64}$/);

        const tokenResult = await pool.query(
            `
                SELECT token_hash AS "tokenHash"
                FROM password_reset_tokens
                WHERE user_id = $1
            `,
            [userId],
        );

        assert.equal(tokenResult.rowCount, 1);
        assert.equal(
            tokenResult.rows[0].tokenHash,
            hashToken(rawToken),
        );
        assert.notEqual(
            tokenResult.rows[0].tokenHash,
            rawToken,
        );
    } finally {
        await deleteTestUser(userId);
    }
});

test('returns the same result for unknown and rate-limited email', async () => {
    let userId;

    try {
        const user = await createTestUser('anonymous');
        userId = user.id;

        const mailer = createFakePasswordResetMailer();

        const firstResult =
            await requestPasswordResetEmail(
                pool,
                user.email,
                mailer,
            );

        const limitedResult =
            await requestPasswordResetEmail(
                pool,
                user.email,
                mailer,
            );

        const unknownResult =
            await requestPasswordResetEmail(
                pool,
                `unknown-${crypto.randomUUID()}@example.com`,
                mailer,
            );

        assert.deepEqual(firstResult, {
            status: 'accepted',
        });
        assert.deepEqual(limitedResult, firstResult);
        assert.deepEqual(unknownResult, firstResult);

        assert.equal(mailer.sentMessages.length, 1);

        const tokenResult = await pool.query(
            `
                SELECT COUNT(*)::INTEGER AS token_count
                FROM password_reset_tokens
                WHERE user_id = $1
            `,
            [userId],
        );

        assert.equal(
            tokenResult.rows[0].token_count,
            1,
        );
    } finally {
        await deleteTestUser(userId);
    }
});

test('limits password reset delivery to five per 24 hours', async () => {
    let userId;

    try {
        const user = await createTestUser('daily-limit');
        userId = user.id;

        const mailer = createFakePasswordResetMailer();

        for (let requestIndex = 0; requestIndex < 5; requestIndex += 1) {
            const result =
                await requestPasswordResetEmail(
                    pool,
                    user.email,
                    mailer,
                );

            assert.deepEqual(result, {
                status: 'accepted',
            });

            assert.equal(
                mailer.sentMessages.length,
                requestIndex + 1,
            );

            await pool.query(
                `
                    UPDATE password_reset_tokens
                    SET created_at =
                        clock_timestamp()
                        - INTERVAL '2 minutes'
                    WHERE user_id = $1
                `,
                [userId],
            );
        }

        const limitedResult =
            await requestPasswordResetEmail(
                pool,
                user.email,
                mailer,
            );

        assert.deepEqual(limitedResult, {
            status: 'accepted',
        });
        assert.equal(mailer.sentMessages.length, 5);

        const tokenResult = await pool.query(
            `
                SELECT COUNT(*)::INTEGER AS token_count
                FROM password_reset_tokens
                WHERE user_id = $1
            `,
            [userId],
        );

        assert.equal(
            tokenResult.rows[0].token_count,
            5,
        );
    } finally {
        await deleteTestUser(userId);
    }
});

test('removes an unused token after delivery failure', async () => {
    let userId;

    try {
        const user = await createTestUser('failure');
        userId = user.id;

        const failingMailer = {
            async sendPasswordResetEmail() {
                throw new Error(
                    'Simulated password reset delivery failure',
                );
            },
        };

        await assert.rejects(
            () => requestPasswordResetEmail(
                pool,
                user.email,
                failingMailer,
            ),
            /Simulated password reset delivery failure/,
        );

        const failedTokenResult = await pool.query(
            `
                SELECT COUNT(*)::INTEGER AS token_count
                FROM password_reset_tokens
                WHERE user_id = $1
            `,
            [userId],
        );

        assert.equal(
            failedTokenResult.rows[0].token_count,
            0,
        );

        const workingMailer =
            createFakePasswordResetMailer();

        assert.deepEqual(
            await requestPasswordResetEmail(
                pool,
                user.email,
                workingMailer,
            ),
            {
                status: 'accepted',
            },
        );

        assert.equal(
            workingMailer.sentMessages.length,
            1,
        );
    } finally {
        await deleteTestUser(userId);
    }
});

test('allows only one concurrent delivery per account', async () => {
    let userId;

    try {
        const user = await createTestUser('concurrency');
        userId = user.id;

        const mailer = createFakePasswordResetMailer();

        const results = await Promise.all([
            requestPasswordResetEmail(
                pool,
                user.email,
                mailer,
            ),
            requestPasswordResetEmail(
                pool,
                user.email,
                mailer,
            ),
        ]);

        assert.deepEqual(results, [
            { status: 'accepted' },
            { status: 'accepted' },
        ]);

        assert.equal(mailer.sentMessages.length, 1);

        const tokenResult = await pool.query(
            `
                SELECT COUNT(*)::INTEGER AS token_count
                FROM password_reset_tokens
                WHERE user_id = $1
            `,
            [userId],
        );

        assert.equal(
            tokenResult.rows[0].token_count,
            1,
        );
    } finally {
        await deleteTestUser(userId);
    }
});