require('dotenv').config();

const {
    test,
} = require('node:test');

const assert = require('node:assert/strict');

const baseUrl =
    process.env.API_BASE_URL ||
    'http://127.0.0.1:3000';

const uuidV4Pattern =
    /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

test('reports process liveness without database details', async () => {
    const response =
        await fetch(`${baseUrl}/health`);

    assert.equal(response.status, 200);
    assert.equal(
        response.headers.get('cache-control'),
        'no-store',
    );
    assert.match(
        response.headers.get('x-request-id'),
        uuidV4Pattern,
    );
    assert.deepEqual(await response.json(), {
        status: 'ok',
        message: "Noah's Ark API is running",
    });
});

test('reports database readiness without exposing details', async () => {
    const response =
        await fetch(`${baseUrl}/readyz`);

    assert.equal(response.status, 200);
    assert.equal(
        response.headers.get('cache-control'),
        'no-store',
    );
    assert.match(
        response.headers.get('x-request-id'),
        uuidV4Pattern,
    );
    assert.deepEqual(await response.json(), {
        status: 'ready',
    });
});

test('does not expose the retired database diagnostic endpoint', async () => {
    const response =
        await fetch(`${baseUrl}/database-health`);

    assert.equal(response.status, 404);
    assert.match(
        response.headers.get('x-request-id'),
        uuidV4Pattern,
    );
    assert.deepEqual(await response.json(), {
        message: 'Route not found',
    });
});
