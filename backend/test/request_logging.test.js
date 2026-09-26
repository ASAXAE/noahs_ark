const {
    EventEmitter,
} = require('node:events');
const {
    test,
} = require('node:test');

const assert = require('node:assert/strict');

const {
    createRequestLogger,
} = require('../src/request_logging');

test('logs a privacy-safe completed request', () => {
    const calls = [];
    let currentTime = 1000;

    const middleware = createRequestLogger({
        log: (level, event, context) => {
            calls.push({
                level,
                event,
                context,
            });
        },
        now: () => currentTime,
    });

    const request = {
        id: 'request-789',
        method: 'POST',
        originalUrl:
            '/thoughts/123?token=secret-token',
        body: {
            content: 'private thought',
        },
    };
    const response = new EventEmitter();

    response.statusCode = 201;

    let nextCalled = false;

    middleware(request, response, () => {
        nextCalled = true;
    });

    request.route = {
        path: '/thoughts/:id',
    };
    currentTime = 1025;
    response.emit('finish');

    assert.equal(nextCalled, true);
    assert.deepEqual(calls, [
        {
            level: 'info',
            event: 'request_completed',
            context: {
                requestId: 'request-789',
                method: 'POST',
                route: '/thoughts/:id',
                statusCode: 201,
                durationMs: 25,
            },
        },
    ]);

    const serializedCalls = JSON.stringify(calls);

    assert.equal(
        serializedCalls.includes('secret-token'),
        false,
    );
    assert.equal(
        serializedCalls.includes('private thought'),
        false,
    );
});
