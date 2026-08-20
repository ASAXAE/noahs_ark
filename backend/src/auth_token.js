const jwt = require('jsonwebtoken');

function createAccessToken(userId) {
    const secret = process.env.JWT_SECRET;

    if (!secret) {
        throw new Error('JWT_SECRET is not configured');
    }

    return jwt.sign(
        {
            sub: String(userId),
        },
        secret,
        {
            expiresIn: process.env.JWT_EXPIRES_IN || '1h',
        },
    );
}

function verifyAccessToken(token) {
    const secret = process.env.JWT_SECRET;

    if (!secret) {
        throw new Error('JWT_SECRET is not configured');
    }

    return jwt.verify(token, secret);
}

module.exports = {
    createAccessToken,
    verifyAccessToken,
};