function notFoundHandler(request, response) {
    return response.status(404).json({
        message: 'Route not found',
    });
}

function createErrorHandler({
    reportRequestError,
}) {
    return function errorHandler(
        error,
        request,
        response,
        next,
    ) {
        if (response.headersSent) {
            return next(error);
        }

        if (error.type === 'entity.parse.failed') {
            return response.status(400).json({
                message: 'Invalid JSON body',
            });
        }

        if (error.type === 'entity.too.large') {
            return response.status(413).json({
                message: 'Request body is too large',
            });
        }

        reportRequestError(
            request,
            'unhandled_request_error',
        );

        return response.status(500).json({
            message: 'Internal server error',
        });
    };
}

module.exports = {
    createErrorHandler,
    notFoundHandler,
};
