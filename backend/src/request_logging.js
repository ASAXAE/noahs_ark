const {
    writeLog,
} = require('./privacy_logger');

function createRequestLogger({
    log = writeLog,
    now = () => Date.now(),
} = {}) {
    return function logCompletedRequest(
        request,
        response,
        next,
    ) {
        const startedAt = now();

        response.once('finish', () => {
            const statusCode = response.statusCode;
            const route =
                typeof request.route?.path === 'string'
                    ? request.route.path
                    : 'unmatched';

            let level = 'info';

            if (statusCode >= 500) {
                level = 'error';
            } else if (statusCode >= 400) {
                level = 'warn';
            }

            log(
                level,
                'request_completed',
                {
                    requestId: request.id,
                    method: request.method,
                    route,
                    statusCode,
                    durationMs: Math.max(
                        0,
                        now() - startedAt,
                    ),
                },
            );
        });

        next();
    };
}

module.exports = {
    createRequestLogger,
};
