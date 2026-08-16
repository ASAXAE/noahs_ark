require('dotenv').config();

const {
    after,
    describe,
    test,
} = require('node:test');

const assert = require('node:assert/strict');
const bcrypt = require('bcryptjs');

const pool = require('../src/database');

const baseUrl =
    process.env.API_BASE_URL ||
    'http://127.0.0.1:3000';

after(async () => {
    await pool.end();
});

describe('Auth API', () => {
    test('registers a user and rejects a duplicate email', async () => {
        const email =
            `integration-${Date.now()}@example.com`;

        const password = 'Integration123!';

        const registrationData = {
            displayName: 'Integration User',
            email,
            password,
        };

        try {
            const registerResponse = await fetch(
                `${baseUrl}/auth/register`,
                {
                    method: 'POST',
                    headers: {
                        'Content-Type':
                            'application/json; charset=utf-8',
                    },
                    body: JSON.stringify(registrationData),
                },
            );

            assert.equal(registerResponse.status, 201);

            const registeredUser =
                await registerResponse.json();

            assert.equal(
                registeredUser.displayName,
                'Integration User',
            );

            assert.equal(registeredUser.email, email);

            assert.equal(registeredUser.password, undefined);
            assert.equal(
                registeredUser.passwordHash,
                undefined,
            );

            const databaseResult = await pool.query(
                `
                    SELECT password_hash
                    FROM users
                    WHERE email = $1
                `,
                [email],
            );

            assert.equal(databaseResult.rows.length, 1);

            const passwordHash =
                databaseResult.rows[0].password_hash;

            assert.notEqual(passwordHash, password);

            const passwordMatches = await bcrypt.compare(
                password,
                passwordHash,
            );

            assert.equal(passwordMatches, true);

            const duplicateResponse = await fetch(
                `${baseUrl}/auth/register`,
                {
                    method: 'POST',
                    headers: {
                        'Content-Type':
                            'application/json; charset=utf-8',
                    },
                    body: JSON.stringify(registrationData),
                },
            );

            assert.equal(duplicateResponse.status, 409);

            const duplicateBody =
                await duplicateResponse.json();

            assert.equal(
                duplicateBody.message,
                'Email is already registered',
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
    test('rejects invalid registration data', async () => {
        const response = await fetch(
            `${baseUrl}/auth/register`,
            {
                method: 'POST',
                headers: {
                    'Content-Type':
                        'application/json; charset=utf-8',
                },
                body: JSON.stringify({
                    displayName: '',
                    email: 'invalid-email',
                    password: '1234567',
                }),
            },
        );

        assert.equal(response.status, 400);

        const responseBody = await response.json();

        assert.equal(
            responseBody.message,
            'Invalid registration data',
        );

        assert.ok(
            responseBody.errors.includes(
                'displayName is required',
            ),
        );

        assert.ok(
            responseBody.errors.includes(
                'email is invalid',
            ),
        );

        assert.ok(
            responseBody.errors.includes(
                'password must contain at least 8 characters',
            ),
        );
    });
});