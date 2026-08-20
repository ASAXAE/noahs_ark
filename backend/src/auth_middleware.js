const {
    verifyAccessToken,
} = require('./auth_token');

function requireAuthentication(request, response, next) {
    const authorizationHeader =
        request.get('authorization');

    if (authorizationHeader === undefined) {
        return response.status(401).json({
            message: 'Authentication required',
        });
    }

    const bearerMatch =
        authorizationHeader.match(/^Bearer\s+(.+)$/i);

    if (bearerMatch === null) {
        return response.status(401).json({
            message: 'Invalid authorization header',
        });
    }

    const accessToken = bearerMatch[1].trim();

    try {
        const tokenPayload =
            verifyAccessToken(accessToken);

        if (
            typeof tokenPayload !== 'object' ||
            typeof tokenPayload.sub !== 'string' ||
            !/^\d+$/.test(tokenPayload.sub)
        ) {
            return response.status(401).json({
                message: 'Invalid access token',
            });
        }

        request.auth = {
            userId: tokenPayload.sub,
        };

        return next();
    } catch (error) {
        return response.status(401).json({
            message: 'Invalid or expired access token',
        });
    }
}

module.exports = {
    requireAuthentication,
};