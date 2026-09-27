const express = require('express');

function createAuthRoutes({
    authController,
    requireAuthentication,
}) {
    const router = express.Router();

    router.post(
        '/auth/register',
        authController.register,
    );
    router.post(
        '/auth/login',
        authController.login,
    );
    router.post(
        '/auth/token/refresh',
        authController.refreshSession,
    );
    router.post(
        '/auth/logout',
        authController.logout,
    );
    router.get(
        '/auth/me',
        requireAuthentication,
        authController.me,
    );
    router.delete(
        '/auth/account',
        requireAuthentication,
        authController.deleteAccount,
    );
    router.post(
        '/auth/email-verification/resend',
        requireAuthentication,
        authController.resendVerification,
    );
    router.post(
        '/auth/email-verification/confirm',
        authController.confirmVerification,
    );
    router.post(
        '/auth/password-reset/request',
        authController.requestPasswordReset,
    );
    router.post(
        '/auth/password-reset/confirm',
        authController.confirmPasswordReset,
    );

    return router;
}

module.exports = {
    createAuthRoutes,
};
