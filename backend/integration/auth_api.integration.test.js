require('dotenv').config();

const {
    after,
    describe,
    test,
} = require('node:test');

const assert = require('node:assert/strict');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');

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

    test('logs in a registered user and rejects invalid credentials', async () => {
        const email =
            `login-${Date.now()}@example.com`;

        const password = 'LoginTest123!';

        try {
            const registerResponse = await fetch(
                `${baseUrl}/auth/register`,
                {
                    method: 'POST',
                    headers: {
                        'Content-Type':
                            'application/json; charset=utf-8',
                    },
                    body: JSON.stringify({
                        displayName: 'Login Test User',
                        email,
                        password,
                    }),
                },
            );

            assert.equal(registerResponse.status, 201);

            const loginResponse = await fetch(
                `${baseUrl}/auth/login`,
                {
                    method: 'POST',
                    headers: {
                        'Content-Type':
                            'application/json; charset=utf-8',
                    },
                    body: JSON.stringify({
                        email,
                        password,
                    }),
                },
            );

           const loginResult = await loginResponse.json();

           assert.equal(
               typeof loginResult.accessToken,
               'string',
           );

           assert.ok(loginResult.accessToken.length > 0);

           assert.equal(
               loginResult.user.displayName,
               'Login Test User',
           );

           assert.equal(loginResult.user.email, email);
           assert.equal(loginResult.user.password, undefined);
           assert.equal(
               loginResult.user.passwordHash,
               undefined,
           );

           const tokenPayload = jwt.verify(
               loginResult.accessToken,
               process.env.JWT_SECRET,
           );

           assert.equal(
               tokenPayload.sub,
               String(loginResult.user.id),
           );

           const meResponse = await fetch(
               `${baseUrl}/auth/me`,
               {
                   headers: {
                       Authorization:
                           `Bearer ${loginResult.accessToken}`,
                   },
               },
           );

           assert.equal(meResponse.status, 200);

           const currentUser = await meResponse.json();

           assert.equal(
               currentUser.id,
               loginResult.user.id,
           );

           assert.equal(
               currentUser.displayName,
               'Login Test User',
           );

           assert.equal(currentUser.email, email);
           assert.equal(currentUser.password, undefined);
           assert.equal(currentUser.passwordHash, undefined);

           const missingTokenResponse = await fetch(
               `${baseUrl}/auth/me`,
           );

           assert.equal(missingTokenResponse.status, 401);

           const invalidTokenResponse = await fetch(
               `${baseUrl}/auth/me`,
               {
                   headers: {
                       Authorization:
                           'Bearer invalid-token',
                   },
               },
           );

           assert.equal(invalidTokenResponse.status, 401);

            const wrongPasswordResponse = await fetch(
                `${baseUrl}/auth/login`,
                {
                    method: 'POST',
                    headers: {
                        'Content-Type':
                            'application/json; charset=utf-8',
                    },
                    body: JSON.stringify({
                        email,
                        password: 'WrongPassword!',
                    }),
                },
            );

            assert.equal(wrongPasswordResponse.status, 401);

            const wrongPasswordBody =
                await wrongPasswordResponse.json();

            assert.equal(
                wrongPasswordBody.message,
                'Invalid email or password',
            );

            const unknownEmailResponse = await fetch(
                `${baseUrl}/auth/login`,
                {
                    method: 'POST',
                    headers: {
                        'Content-Type':
                            'application/json; charset=utf-8',
                    },
                    body: JSON.stringify({
                        email: 'unknown@example.com',
                        password,
                    }),
                },
            );

            assert.equal(unknownEmailResponse.status, 401);

            const unknownEmailBody =
                await unknownEmailResponse.json();

            assert.equal(
                unknownEmailBody.message,
                'Invalid email or password',
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
});