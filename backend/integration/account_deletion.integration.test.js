require('dotenv').config();

const assert = require('node:assert/strict');
const bcrypt = require('bcryptjs');
const crypto = require('node:crypto');
const { after, test } = require('node:test');

const pool = require('../src/database');

const {
    deleteAccountWithPassword,
} = require('../src/account_deletion');

const {
    issueEmailVerificationToken,
} = require('../src/email_verification');

const {
    issueRefreshToken,
    rotateRefreshToken,
} = require('../src/refresh_token');

const {
    issuePasswordResetToken,
} = require('../src/password_reset');

process.env.REFRESH_TOKEN_TTL_DAYS = '30';
process.env.PASSWORD_RESET_TOKEN_TTL_MINUTES = '60';

const currentPassword = 'CurrentPassword123';

after(async () => {
    await pool.end();
});

async function createTestAccount(label) {
    const passwordHash = await bcrypt.hash(
        currentPassword,
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
            `Deletion ${label}`,
            `deletion-${label}-${crypto.randomUUID()}@example.com`,
            passwordHash,
        ],
    );

    return result.rows[0].id;
}

async function seedCloudData(userId) {
    await pool.query(
        `
            INSERT INTO thoughts (
                user_id,
                title,
                content,
                tag
            )
            VALUES ($1, $2, $3, $4)
        `,
        [
            userId,
            'Cloud thought',
            'This record belongs to the server account.',
            '学习',
        ],
    );

    await issueEmailVerificationToken(pool, userId);

    const refreshSession = await issueRefreshToken(
        pool,
        userId,
    );

    await issuePasswordResetToken(pool, userId);

    return refreshSession;
}

async function getCloudRowCounts(userId) {
    const result = await pool.query(
        `
            SELECT
                (
                    SELECT COUNT(*)::INTEGER
                    FROM users
                    WHERE id = $1
                ) AS "userCount",
                (
                    SELECT COUNT(*)::INTEGER
                    FROM thoughts
                    WHERE user_id = $1
                ) AS "thoughtCount",
                (
                    SELECT COUNT(*)::INTEGER
                    FROM email_verification_tokens
                    WHERE user_id = $1
                ) AS "verificationTokenCount",
                (
                    SELECT COUNT(*)::INTEGER
                    FROM refresh_tokens
                    WHERE user_id = $1
                ) AS "refreshTokenCount",
                (
                    SELECT COUNT(*)::INTEGER
                    FROM password_reset_tokens
                    WHERE user_id = $1
                ) AS "passwordResetTokenCount"
        `,
        [userId],
    );

    return result.rows[0];
}

async function deleteTestAccount(userId) {
    if (userId === undefined) {
        return;
    }

    await pool.query(
        'DELETE FROM users WHERE id = $1',
        [userId],
    );
}

test('deletes the account and all related cloud data', async () => {
    let userId;

    try {
        userId = await createTestAccount('cascade');

        const refreshSession = await seedCloudData(
            userId,
        );

        const deleted = await deleteAccountWithPassword(
            pool,
            String(userId),
            currentPassword,
        );

        assert.equal(deleted, true);

        assert.deepEqual(
            await getCloudRowCounts(userId),
            {
                userCount: 0,
                thoughtCount: 0,
                verificationTokenCount: 0,
                refreshTokenCount: 0,
                passwordResetTokenCount: 0,
            },
        );

        assert.deepEqual(
            await rotateRefreshToken(
                pool,
                refreshSession.refreshToken,
            ),
            {
                status: 'invalid',
            },
        );
    } finally {
        await deleteTestAccount(userId);
    }
});

test('wrong password leaves the account and cloud data unchanged', async () => {
    let userId;

    try {
        userId = await createTestAccount('wrong-password');

        await seedCloudData(userId);

        const deleted = await deleteAccountWithPassword(
            pool,
            String(userId),
            'WrongPassword456',
        );

        assert.equal(deleted, false);

        assert.deepEqual(
            await getCloudRowCounts(userId),
            {
                userCount: 1,
                thoughtCount: 1,
                verificationTokenCount: 1,
                refreshTokenCount: 1,
                passwordResetTokenCount: 1,
            },
        );
    } finally {
        await deleteTestAccount(userId);
    }
});