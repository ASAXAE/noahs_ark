require('dotenv').config();

const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const jwt = require('jsonwebtoken');
const { after, test } = require('node:test');

const pool = require('../src/database');

const baseUrl =
    process.env.API_BASE_URL ||
    'http://127.0.0.1:3000';

after(async () => {
    await pool.end();
});

function hashToken(rawToken) {
    return crypto
        .createHash('sha256')
        .update(rawToken)
        .digest('hex');
}

function postJson(path, body) {
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

test('login, rotation, reuse detection and logout form one session flow', async () => {
    const email =
        `session-${crypto.randomUUID()}@example.com`;

    const password = 'SessionTest123!';

    try {
        const registerResponse = await postJson(
            '/auth/register',
            {
                displayName: 'Session Test User',
                email,
                password,
            },
        );

        assert.equal(
            registerResponse.status,
            201,
        );

        const registeredUser =
            await registerResponse.json();

        const loginResponse = await postJson(
            '/auth/login',
            {
                email,
                password,
            },
        );

        assert.equal(
            loginResponse.status,
            200,
        );

        const loginSession =
            await loginResponse.json();

        assert.equal(
            typeof loginSession.accessToken,
            'string',
        );

        assert.match(
            loginSession.refreshToken,
            /^[0-9a-f]{64}$/,
        );

        assert.equal(
            Number.isNaN(
                Date.parse(
                    loginSession.refreshTokenExpiresAt,
                ),
            ),
            false,
        );

        const accessPayload = jwt.verify(
            loginSession.accessToken,
            process.env.JWT_SECRET,
        );

        assert.equal(
            accessPayload.sub,
            String(registeredUser.id),
        );

        assert.equal(
            accessPayload.exp - accessPayload.iat,
            15 * 60,
        );

        const storedResult = await pool.query(
            `
                SELECT
                    token_hash,
                    family_id,
                    expires_at,
                    rotated_at,
                    revoked_at
                FROM refresh_tokens
                WHERE user_id = $1
                ORDER BY id
            `,
            [registeredUser.id],
        );

        assert.equal(
            storedResult.rowCount,
            1,
        );

        assert.equal(
            storedResult.rows[0].token_hash,
            hashToken(loginSession.refreshToken),
        );

        assert.notEqual(
            storedResult.rows[0].token_hash,
            loginSession.refreshToken,
        );

        assert.equal(
            storedResult.rows[0].rotated_at,
            null,
        );

        assert.equal(
            storedResult.rows[0].revoked_at,
            null,
        );

        const refreshResponse = await postJson(
            '/auth/token/refresh',
            {
                refreshToken:
                    loginSession.refreshToken,
            },
        );

        assert.equal(
            refreshResponse.status,
            200,
        );

        const refreshedSession =
            await refreshResponse.json();

        assert.equal(
            typeof refreshedSession.accessToken,
            'string',
        );

        assert.match(
            refreshedSession.refreshToken,
            /^[0-9a-f]{64}$/,
        );

        assert.notEqual(
            refreshedSession.refreshToken,
            loginSession.refreshToken,
        );

        assert.equal(
            refreshedSession.refreshTokenExpiresAt,
            loginSession.refreshTokenExpiresAt,
        );

        const refreshedPayload = jwt.verify(
            refreshedSession.accessToken,
            process.env.JWT_SECRET,
        );

        assert.equal(
            refreshedPayload.sub,
            String(registeredUser.id),
        );

        assert.equal(
            refreshedPayload.exp - refreshedPayload.iat,
            15 * 60,
        );

        const replayResponse = await postJson(
            '/auth/token/refresh',
            {
                refreshToken:
                    loginSession.refreshToken,
            },
        );

        assert.equal(
            replayResponse.status,
            401,
        );

        const replayBody =
            await replayResponse.json();

        assert.equal(
            replayBody.message,
            'Invalid or expired refresh token',
        );

        const revokedReplacementResponse =
            await postJson(
                '/auth/token/refresh',
                {
                    refreshToken:
                        refreshedSession.refreshToken,
                },
            );

        assert.equal(
            revokedReplacementResponse.status,
            401,
        );

        const secondLoginResponse = await postJson(
            '/auth/login',
            {
                email,
                password,
            },
        );

        assert.equal(
            secondLoginResponse.status,
            200,
        );

        const secondLoginSession =
            await secondLoginResponse.json();

        assert.notEqual(
            secondLoginSession.refreshToken,
            refreshedSession.refreshToken,
        );

        const logoutResponse = await postJson(
            '/auth/logout',
            {
                refreshToken:
                    secondLoginSession.refreshToken,
            },
        );

        assert.equal(
            logoutResponse.status,
            204,
        );

        const refreshAfterLogoutResponse =
            await postJson(
                '/auth/token/refresh',
                {
                    refreshToken:
                        secondLoginSession.refreshToken,
                },
            );

        assert.equal(
            refreshAfterLogoutResponse.status,
            401,
        );

        const meAfterLogoutResponse = await fetch(
            `${baseUrl}/auth/me`,
            {
                headers: {
                    Authorization:
                        `Bearer ${secondLoginSession.accessToken}`,
                },
            },
        );

        assert.equal(
            meAfterLogoutResponse.status,
            200,
        );

        const activeResult = await pool.query(
            `
                SELECT
                    COUNT(*) FILTER (
                        WHERE revoked_at IS NULL
                            AND expires_at >
                                clock_timestamp()
                    )::INTEGER AS active_count
                FROM refresh_tokens
                WHERE user_id = $1
            `,
            [registeredUser.id],
        );

        assert.equal(
            activeResult.rows[0].active_count,
            0,
        );

        const invalidRefreshResponse =
            await postJson(
                '/auth/token/refresh',
                {
                    refreshToken: 'invalid-token',
                },
            );

        assert.equal(
            invalidRefreshResponse.status,
            401,
        );

        const invalidLogoutResponse =
            await postJson(
                '/auth/logout',
                {
                    refreshToken: 'invalid-token',
                },
            );

        assert.equal(
            invalidLogoutResponse.status,
            204,
        );
    } finally {
        await pool.query(
            `
                DELETE FROM users
                WHERE email = $1
            `,
            [email],
        );
    }
});
