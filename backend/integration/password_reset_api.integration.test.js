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
} = require('../src/password_reset');

const baseUrl =
    process.env.API_BASE_URL ||
    'http://127.0.0.1:3000';

const originalPassword = 'OriginalPassword123';
const replacementPassword = 'ReplacementPassword456';

after(async () => {
    await pool.end();
});

async function createTestUser(label) {
    const uniqueValue =
        `${Date.now()}-${crypto.randomUUID()}`;

    const email =
        `reset-api-${label}-${uniqueValue}@example.com`;

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
            RETURNING id, email
        `,
        [
            `Reset API ${label}`,
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

async function postJson(path, body) {
    return fetch(
        `${baseUrl}${path}`,
        {
            method: 'POST',
            headers: {
                'Content-Type':
                    'application/json; charset=utf-8',
            },
            body: JSON.stringify(body),
        },
    );
}

test('does not disclose whether a reset email exists', async () => {
    let userId;

    try {
        const user = await createTestUser('anonymous');
        userId = user.id;

        const existingResponse = await postJson(
            '/auth/password-reset/request',
            {
                email: user.email,
            },
        );

        assert.equal(existingResponse.status, 202);

        const existingBody =
            await existingResponse.json();

        const limitedResponse = await postJson(
            '/auth/password-reset/request',
            {
                email: user.email,
            },
        );

        assert.equal(limitedResponse.status, 202);

        const limitedBody =
            await limitedResponse.json();

        const unknownResponse = await postJson(
            '/auth/password-reset/request',
            {
                email:
                    `unknown-${crypto.randomUUID()}@example.com`,
            },
        );

        assert.equal(unknownResponse.status, 202);

        const unknownBody =
            await unknownResponse.json();

        assert.deepEqual(limitedBody, existingBody);
        assert.deepEqual(unknownBody, existingBody);

        assert.deepEqual(existingBody, {
            message:
                'If the email is registered, password reset instructions will be sent',
        });

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

        const invalidResponse = await postJson(
            '/auth/password-reset/request',
            {
                email: 'invalid-email',
            },
        );

        assert.equal(invalidResponse.status, 400);
    } finally {
        await deleteTestUser(userId);
    }
});

test('resets password and rejects the previous session', async () => {
    let userId;

    try {
        const user = await createTestUser('confirmation');
        userId = user.id;

        const loginResponse = await postJson(
            '/auth/login',
            {
                email: user.email,
                password: originalPassword,
            },
        );

        assert.equal(loginResponse.status, 200);

        const loginBody = await loginResponse.json();
        const oldRefreshToken =
            loginBody.refreshToken;

        const resetToken =
            await issuePasswordResetToken(
                pool,
                userId,
            );

        const invalidResponse = await postJson(
            '/auth/password-reset/confirm',
            {
                token: 'invalid-token',
                password: 'short',
            },
        );

        assert.equal(invalidResponse.status, 400);

        const resetResponse = await postJson(
            '/auth/password-reset/confirm',
            {
                token: resetToken,
                password: replacementPassword,
            },
        );

        assert.equal(resetResponse.status, 200);
        assert.deepEqual(
            await resetResponse.json(),
            {
                reset: true,
            },
        );

        const replayResponse = await postJson(
            '/auth/password-reset/confirm',
            {
                token: resetToken,
                password: replacementPassword,
            },
        );

        assert.equal(replayResponse.status, 400);

        const refreshResponse = await postJson(
            '/auth/token/refresh',
            {
                refreshToken: oldRefreshToken,
            },
        );

        assert.equal(refreshResponse.status, 401);

        const oldPasswordResponse = await postJson(
            '/auth/login',
            {
                email: user.email,
                password: originalPassword,
            },
        );

        assert.equal(oldPasswordResponse.status, 401);

        const newPasswordResponse = await postJson(
            '/auth/login',
            {
                email: user.email,
                password: replacementPassword,
            },
        );

        assert.equal(newPasswordResponse.status, 200);
    } finally {
        await deleteTestUser(userId);
    }
});