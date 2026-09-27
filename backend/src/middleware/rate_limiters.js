const {
    rateLimit,
} = require('express-rate-limit');

const sensitiveAuthLimiter = rateLimit({
    windowMs: 15 * 60 * 1000,
    limit: 40,
    standardHeaders: 'draft-8',
    legacyHeaders: false,
    identifier: 'sensitive-auth',
    message: {
        message:
            'Too many authentication requests; try again later',
    },
});

const sessionTokenLimiter = rateLimit({
    windowMs: 15 * 60 * 1000,
    limit: 120,
    standardHeaders: 'draft-8',
    legacyHeaders: false,
    identifier: 'session-token',
    message: {
        message:
            'Too many session requests; try again later',
    },
});

module.exports = {
    sensitiveAuthLimiter,
    sessionTokenLimiter,
};
