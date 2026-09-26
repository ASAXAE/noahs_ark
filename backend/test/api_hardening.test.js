const {
    after,
    before,
    test,
} = require('node:test');

const assert = require('node:assert/strict');

const app = require('../src/server');

let server;
let baseUrl;

before(async () => {
    await new Promise((resolve, reject) => {
        server = app.listen(
            0,
            '127.0.0.1',
            () => {
                const address = server.address();

                baseUrl =
                    `http://127.0.0.1:${address.port}`;

                resolve();
            },
        );

        server.on('error', reject);
    });
});

after(async () => {
    await new Promise((resolve, reject) => {
        server.close((error) => {
            if (error !== undefined) {
                reject(error);
                return;
            }

            resolve();
        });
    });
});

test('sets API security headers', async () => {
    const response = await fetch(`${baseUrl}/health`);

    assert.equal(response.status, 200);
    assert.equal(
        response.headers.get('x-content-type-options'),
        'nosniff',
    );
    assert.equal(
        response.headers.get('referrer-policy'),
        'no-referrer',
    );
    assert.equal(
        response.headers.get('x-powered-by'),
        null,
    );
    assert.equal(
        response.headers.get(
            'strict-transport-security',
        ),
        null,
    );
    assert.equal(
        response.headers.get(
            'content-security-policy',
        ),
        null,
    );
});

test('adds a unique request ID to every response', async () => {
    const firstResponse = await fetch(
        `${baseUrl}/health`,
    );
    const secondResponse = await fetch(
        `${baseUrl}/unknown-route`,
    );

    const firstRequestId =
        firstResponse.headers.get('x-request-id');
    const secondRequestId =
        secondResponse.headers.get('x-request-id');

    const uuidV4Pattern =
        /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

    assert.match(firstRequestId, uuidV4Pattern);
    assert.match(secondRequestId, uuidV4Pattern);
    assert.notEqual(firstRequestId, secondRequestId);
});

test('returns a JSON 404 response', async () => {
    const response = await fetch(
        `${baseUrl}/unknown-route`,
    );

    assert.equal(response.status, 404);
    assert.deepEqual(await response.json(), {
        message: 'Route not found',
    });
});

test('rejects malformed JSON', async () => {
    const response = await fetch(
        `${baseUrl}/thoughts`,
        {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
            },
            body: '{bad',
        },
    );

    assert.equal(response.status, 400);
    assert.deepEqual(await response.json(), {
        message: 'Invalid JSON body',
    });
});

test('rejects JSON bodies larger than 32 KB', async () => {
    const response = await fetch(
        `${baseUrl}/thoughts`,
        {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
            },
            body: JSON.stringify({
                content: 'a'.repeat(33 * 1024),
            }),
        },
    );

    assert.equal(response.status, 413);
    assert.deepEqual(await response.json(), {
        message: 'Request body is too large',
    });
});

test('limits repeated sensitive authentication requests', async () => {
    for (let attempt = 1; attempt <= 40; attempt++) {
        const response = await fetch(
            `${baseUrl}/auth/register`,
            {
                method: 'POST',
                headers: {
                    'Content-Type':
                        'application/json',
                },
                body: '{}',
            },
        );

        assert.equal(
            response.status,
            400,
            `attempt ${attempt}`,
        );
    }

    const blockedResponse = await fetch(
        `${baseUrl}/auth/register`,
        {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
            },
            body: '{}',
        },
    );

    assert.equal(blockedResponse.status, 429);
    assert.match(
        blockedResponse.headers.get('ratelimit'),
        /sensitive-auth/,
    );
    assert.match(
        blockedResponse.headers.get(
            'ratelimit-policy',
        ),
        /q=40/,
    );
    assert.notEqual(
        blockedResponse.headers.get('retry-after'),
        null,
    );
    assert.equal(
        blockedResponse.headers.get(
            'x-ratelimit-limit',
        ),
        null,
    );
    assert.deepEqual(
        await blockedResponse.json(),
        {
            message:
                'Too many authentication requests; try again later',
        },
    );
});
