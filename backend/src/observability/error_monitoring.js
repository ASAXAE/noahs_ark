const {
    writeLog,
} = require('./privacy_logger');

function createRequestContext(
    request,
    errorCode,
    statusCode,
) {
    const route =
        typeof request.route?.path === 'string'
            ? request.route.path
            : 'unmatched';

    return {
        requestId: request.id,
        method: request.method,
        route,
        statusCode,
        errorCode,
    };
}

function createErrorReporter({
    log = writeLog,
} = {}) {
    return function reportRequestError(
        request,
        errorCode,
        statusCode = 500,
    ) {
        return log(
            statusCode >= 500 ? 'error' : 'warn',
            'request_failed',
            createRequestContext(
                request,
                errorCode,
                statusCode,
            ),
        );
    };
}

function createOperationalErrorReporter({
    log = writeLog,
} = {}) {
    return function reportOperationalError(
        request,
        errorCode,
        statusCode,
    ) {
        return log(
            'error',
            'operation_failed',
            createRequestContext(
                request,
                errorCode,
                statusCode,
            ),
        );
    };
}

function createSecurityEventReporter({
    log = writeLog,
} = {}) {
    return function reportSecurityEvent(
        request,
        eventCode,
        statusCode = 401,
    ) {
        return log(
            'warn',
            'security_event',
            createRequestContext(
                request,
                eventCode,
                statusCode,
            ),
        );
    };
}

module.exports = {
    createErrorReporter,
    createOperationalErrorReporter,
    createSecurityEventReporter,
};
