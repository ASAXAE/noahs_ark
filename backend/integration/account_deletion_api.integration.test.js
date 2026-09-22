require('dotenv').config();

const assert = require('node:assert/strict');
const bcrypt = require('bcryptjs');
const crypto = require('node:crypto');
const { after, test } = require('node:test');

const pool = require('../src/database');

const baseUrl =
    process.env.API_BASE_URL ||
    'http://127.0.0.1:3000';

const currentPassword = 'CurrentPassword123';

after(async () => {
    await pool.end();
});

async function createTestAccount() {
    const email =
        `deletion-api-${crypto.randomUUID()}@example.com`;

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
            'Deletion API',
            email,
            passwordHash,
        ],
    );

    return {
        userId: result.rows[0].id,
        email,
    };
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

async function sendJson(
    path,
    {
        method = 'POST',
        accessToken,
        body,
    } = {},
) {
    const headers = {};

    if (body !== undefined) {
        headers['Content-Type'] =
            'application/json; charset=utf-8';
    }

    if (accessToken !== undefined) {
        headers.Authorization =
            `Bearer ${accessToken}`;
    }

    return fetch(
        `${baseUrl}${path}`,
        {
            method,
            headers,
            body:
                body === undefined
                    ? undefined
                    : JSON.stringify(body),
        },
    );
}

test('deletes an authenticated account through the API', async () => {
    let userId;

    try {
        const account = await createTestAccount();

        userId = account.userId;

        const unauthenticatedResponse = await sendJson(
            '/auth/account',
            {
                method: 'DELETE',
                body: {
                    password: currentPassword,
                },
            },
        );

        assert.equal(
            unauthenticatedResponse.status,
            401,
        );

        const loginResponse = await sendJson(
            '/auth/login',
            {
                body: {
                    email: account.email,
                    password: currentPassword,
                },
            },
        );

        assert.equal(loginResponse.status, 200);

        const loginBody = await loginResponse.json();

        const invalidResponse = await sendJson(
            '/auth/account',
            {
                method: 'DELETE',
                accessToken: loginBody.accessToken,
                body: {},
            },
        );

        assert.equal(invalidResponse.status, 400);

        const wrongPasswordResponse = await sendJson(
            '/auth/account',
            {
                method: 'DELETE',
                accessToken: loginBody.accessToken,
                body: {
                    password: 'WrongPassword456',
                },
            },
        );

        assert.equal(
            wrongPasswordResponse.status,
            403,
        );

        const existingAccountResponse = await sendJson(
            '/auth/me',
            {
                method: 'GET',
                accessToken: loginBody.accessToken,
            },
        );

        assert.equal(
            existingAccountResponse.status,
            200,
        );

        const deletionResponse = await sendJson(
            '/auth/account',
            {
                method: 'DELETE',
                accessToken: loginBody.accessToken,
                body: {
                    password: currentPassword,
                },
            },
        );

        assert.equal(deletionResponse.status, 204);

        const deletedUserResult = await pool.query(
            `
                SELECT id
                FROM users
                WHERE id = $1
            `,
            [userId],
        );

        assert.equal(deletedUserResult.rowCount, 0);

        const oldAccessResponse = await sendJson(
            '/auth/me',
            {
                method: 'GET',
                accessToken: loginBody.accessToken,
            },
        );

        assert.equal(oldAccessResponse.status, 401);

        const oldRefreshResponse = await sendJson(
            '/auth/token/refresh',
            {
                body: {
                    refreshToken:
                        loginBody.refreshToken,
                },
            },
        );

        assert.equal(oldRefreshResponse.status, 401);

        const oldLoginResponse = await sendJson(
            '/auth/login',
            {
                body: {
                    email: account.email,
                    password: currentPassword,
                },
            },
        );

        assert.equal(oldLoginResponse.status, 401);
    } finally {
        await deleteTestAccount(userId);
    }
});