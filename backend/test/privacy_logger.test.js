const {
    test,
} = require('node:test');

const assert = require('node:assert/strict');

const {
    createLogEntry,
    writeLog,
} = require('../src/privacy_logger');

test('creates an allowlisted privacy-safe log entry', () => {
    const now =
        new Date('2026-09-26T00:00:00.000Z');

    const entry = createLogEntry(
        'error',
        'request_failed',
        {
            requestId: 'request-123',
            method: 'POST',
            route: '/auth/login',
            statusCode: 500,
            durationMs: 12,
            errorCode: 'internal_error',

            email: 'private@example.com',
            password: 'secret-password',
            authorization: 'Bearer secret-token',
            refreshToken: 'refresh-secret',
            url: '/confirm?token=secret',
            body: {
                content: 'private thought',
            },
            stack: 'private stack trace',
        },
        now,
    );

    assert.deepEqual(entry, {
        timestamp: '2026-09-26T00:00:00.000Z',
        level: 'error',
        event: 'request_failed',
        requestId: 'request-123',
        method: 'POST',
        route: '/auth/login',
        statusCode: 500,
        durationMs: 12,
        errorCode: 'internal_error',
    });
});

test('writes one structured JSON line at the matching level', () => {
    const lines = {
        log: [],
        warn: [],
        error: [],
    };
    const output = {
        log: (line) => lines.log.push(line),
        warn: (line) => lines.warn.push(line),
        error: (line) => lines.error.push(line),
    };
    const now =
        new Date('2026-09-26T00:00:00.000Z');

    const entry = writeLog(
        'error',
        'request_failed',
        {
            requestId: 'request-456',
            statusCode: 500,
            password: 'must-not-appear',
        },
        output,
        now,
    );

    assert.deepEqual(lines.log, []);
    assert.deepEqual(lines.warn, []);
    assert.deepEqual(
        lines.error,
        [JSON.stringify(entry)],
    );
    assert.equal(
        lines.error[0].includes('must-not-appear'),
        false,
    );
});
