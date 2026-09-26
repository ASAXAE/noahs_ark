const {
    test,
} = require('node:test');

const assert = require('node:assert/strict');

const {
    createErrorReporter,
    createOperationalErrorReporter,
    createSecurityEventReporter,
} = require('../src/error_monitoring');

test('reports a request error without sensitive request data', () => {
    const calls = [];

    const reportRequestError =
        createErrorReporter({
            log: (level, event, context) => {
                calls.push({
                    level,
                    event,
                    context,
                });
            },
        });

    const request = {
        id: 'request-error-123',
        method: 'POST',
        route: {
            path: '/auth/login',
        },
        originalUrl:
            '/auth/login?token=must-not-appear',
        body: {
            email: 'private@example.com',
            password: 'must-not-appear',
        },
    };

    reportRequestError(
        request,
        'login_failed',
        500,
    );

    assert.deepEqual(calls, [
        {
            level: 'error',
            event: 'request_failed',
            context: {
                requestId: 'request-error-123',
                method: 'POST',
                route: '/auth/login',
                statusCode: 500,
                errorCode: 'login_failed',
            },
        },
    ]);

    const serializedCalls = JSON.stringify(calls);

    assert.equal(
        serializedCalls.includes('private@example.com'),
        false,
    );
    assert.equal(
        serializedCalls.includes('must-not-appear'),
        false,
    );
});

test('reports an operational error with the actual response status', () => {
    const calls = [];

    const reportOperationalError =
        createOperationalErrorReporter({
            log: (level, event, context) => {
                calls.push({
                    level,
                    event,
                    context,
                });
            },
        });

    reportOperationalError(
        {
            id: 'request-operation-123',
            method: 'POST',
            route: {
                path: '/auth/password-reset/request',
            },
        },
        'password_reset_delivery_failed',
        202,
    );

    assert.deepEqual(calls, [
        {
            level: 'error',
            event: 'operation_failed',
            context: {
                requestId: 'request-operation-123',
                method: 'POST',
                route: '/auth/password-reset/request',
                statusCode: 202,
                errorCode:
                    'password_reset_delivery_failed',
            },
        },
    ]);
});

test('reports a privacy-safe security event', () => {
    const calls = [];

    const reportSecurityEvent =
        createSecurityEventReporter({
            log: (level, event, context) => {
                calls.push({
                    level,
                    event,
                    context,
                });
            },
        });

    reportSecurityEvent(
        {
            id: 'request-security-123',
            method: 'POST',
            route: {
                path: '/auth/token/refresh',
            },
            body: {
                refreshToken: 'must-not-appear',
            },
        },
        'refresh_token_reuse_detected',
    );

    assert.deepEqual(calls, [
        {
            level: 'warn',
            event: 'security_event',
            context: {
                requestId: 'request-security-123',
                method: 'POST',
                route: '/auth/token/refresh',
                statusCode: 401,
                errorCode:
                    'refresh_token_reuse_detected',
            },
        },
    ]);
    assert.equal(
        JSON.stringify(calls).includes(
            'must-not-appear',
        ),
        false,
    );
});
