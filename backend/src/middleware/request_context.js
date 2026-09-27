const {
    randomUUID,
} = require('node:crypto');

function attachRequestId(request, response, next) {
    const requestId = randomUUID();

    request.id = requestId;
    response.setHeader('X-Request-ID', requestId);

    next();
}

module.exports = {
    attachRequestId,
};
