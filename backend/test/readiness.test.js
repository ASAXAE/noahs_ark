const {
    test,
} = require('node:test');

const assert = require('node:assert/strict');

const {
    checkDatabaseReadiness,
} = require('../src/readiness');

test('reports ready after a bounded database query', async () => {
    let receivedQuery;

    const database = {
        query: async (query) => {
            receivedQuery = query;

            return {
                rows: [
                    {
                        value: 1,
                    },
                ],
            };
        },
    };

    const isReady =
        await checkDatabaseReadiness(database);

    assert.equal(isReady, true);
    assert.deepEqual(receivedQuery, {
        text: 'SELECT 1',
        query_timeout: 3000,
    });
});

test('reports unavailable without exposing the database error', async () => {
    const database = {
        query: async () => {
            throw new Error(
                'password=must-not-be-exposed',
            );
        },
    };

    const isReady =
        await checkDatabaseReadiness(database);

    assert.equal(isReady, false);
});
