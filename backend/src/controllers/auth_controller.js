function createAuthController({
    authService,
    reportRequestError,
    reportOperationalError,
    reportSecurityEvent,
}) {
    return {
        async register(request, response) {
            try {
                const result =
                    await authService.register(request.body);

                if (result.status === 'invalid') {
                    return response.status(400).json({
                        message: 'Invalid registration data',
                        errors: result.errors,
                    });
                }

                if (result.status === 'conflict') {
                    return response.status(409).json({
                        message: 'Email is already registered',
                    });
                }

                if (result.deliveryFailed) {
                    reportOperationalError(
                        request,
                        'initial_verification_delivery_failed',
                        201,
                    );
                }

                return response.status(201).json(
                    result.user,
                );
            } catch {
                reportRequestError(
                    request,
                    'registration_failed',
                );

                return response.status(500).json({
                    message: 'Failed to register user',
                });
            }
        },

        async login(request, response) {
            try {
                const result =
                    await authService.login(request.body);

                if (result.status === 'invalid') {
                    return response.status(400).json({
                        message: 'Invalid login data',
                        errors: result.errors,
                    });
                }

                if (result.status === 'unauthorized') {
                    return response.status(401).json({
                        message: 'Invalid email or password',
                    });
                }

                return response.status(200).json({
                    accessToken: result.accessToken,
                    refreshToken: result.refreshToken,
                    refreshTokenExpiresAt:
                        result.refreshTokenExpiresAt,
                    user: result.user,
                });
            } catch {
                reportRequestError(
                    request,
                    'login_failed',
                );

                return response.status(500).json({
                    message: 'Failed to log in user',
                });
            }
        },

        async refreshSession(request, response) {
            try {
                const result =
                    await authService.refreshSession(
                        request.body?.refreshToken,
                    );

                if (result.status !== 'rotated') {
                    if (result.status === 'reused') {
                        reportSecurityEvent(
                            request,
                            'refresh_token_reuse_detected',
                        );
                    }

                    return response.status(401).json({
                        message:
                            'Invalid or expired refresh token',
                    });
                }

                return response.status(200).json({
                    accessToken: result.accessToken,
                    refreshToken: result.refreshToken,
                    refreshTokenExpiresAt:
                        result.refreshTokenExpiresAt,
                });
            } catch {
                reportRequestError(
                    request,
                    'session_refresh_failed',
                );

                return response.status(500).json({
                    message: 'Failed to refresh session',
                });
            }
        },

        async logout(request, response) {
            try {
                await authService.logout(
                    request.body?.refreshToken,
                );

                return response.status(204).send();
            } catch {
                reportRequestError(
                    request,
                    'session_revocation_failed',
                );

                return response.status(500).json({
                    message: 'Failed to revoke session',
                });
            }
        },

        async me(request, response) {
            try {
                const result =
                    await authService.getCurrentUser(
                        request.auth.userId,
                    );

                if (result.status === 'not_found') {
                    return response.status(401).json({
                        message: 'User account not found',
                    });
                }

                return response.status(200).json(
                    result.user,
                );
            } catch {
                reportRequestError(
                    request,
                    'authenticated_user_fetch_failed',
                );

                return response.status(500).json({
                    message:
                        'Failed to fetch authenticated user',
                });
            }
        },

        async deleteAccount(request, response) {
            try {
                const result =
                    await authService.deleteAccount(
                        request.auth.userId,
                        request.body,
                    );

                if (result.status === 'invalid') {
                    return response.status(400).json({
                        message:
                            'Invalid account deletion data',
                        errors: result.errors,
                    });
                }

                if (
                    result.status ===
                    'incorrect_password'
                ) {
                    return response.status(403).json({
                        message:
                            'Current password is incorrect',
                    });
                }

                return response.status(204).send();
            } catch {
                reportRequestError(
                    request,
                    'account_deletion_failed',
                );

                return response.status(500).json({
                    message: 'Failed to delete account',
                });
            }
        },

        async resendVerification(request, response) {
            try {
                const result =
                    await authService.requestVerification(
                        request.auth.userId,
                    );

                if (result.status === 'not_configured') {
                    return response.status(503).json({
                        message:
                            'Email delivery is not configured',
                    });
                }

                if (result.status === 'rate_limited') {
                    return response.status(429).json({
                        message:
                            'Please wait before requesting another verification email',
                    });
                }

                return response.status(202).json({
                    message:
                        'Verification request accepted',
                });
            } catch {
                reportRequestError(
                    request,
                    'verification_request_failed',
                    503,
                );

                return response.status(503).json({
                    message:
                        'Verification email is temporarily unavailable',
                });
            }
        },

        async confirmVerification(request, response) {
            try {
                const result =
                    await authService.confirmVerification(
                        request.body?.token,
                    );

                if (result.status === 'invalid') {
                    return response.status(400).json({
                        message:
                            'Invalid or expired verification token',
                    });
                }

                return response.status(200).json({
                    verified: true,
                });
            } catch {
                reportRequestError(
                    request,
                    'verification_confirmation_failed',
                );

                return response.status(500).json({
                    message:
                        'Failed to confirm email verification',
                });
            }
        },

        async requestPasswordReset(request, response) {
            const result =
                await authService.requestPasswordReset(
                    request.body,
                );

            if (result.status === 'invalid') {
                return response.status(400).json({
                    message:
                        'Invalid password reset request',
                    errors: result.errors,
                });
            }

            if (result.status === 'not_configured') {
                return response.status(503).json({
                    message:
                        'Email delivery is not configured',
                });
            }

            if (result.deliveryFailed) {
                reportOperationalError(
                    request,
                    'password_reset_delivery_failed',
                    202,
                );
            }

            return response.status(202).json({
                message:
                    'If the email is registered, password reset instructions will be sent',
            });
        },

        async confirmPasswordReset(request, response) {
            try {
                const result =
                    await authService.confirmPasswordReset(
                        request.body,
                    );

                if (result.status === 'invalid_input') {
                    return response.status(400).json({
                        message:
                            'Invalid password reset data',
                        errors: result.errors,
                    });
                }

                if (result.status === 'invalid_token') {
                    return response.status(400).json({
                        message:
                            'Invalid or expired password reset token',
                    });
                }

                return response.status(200).json({
                    reset: true,
                });
            } catch {
                reportRequestError(
                    request,
                    'password_reset_failed',
                );

                return response.status(500).json({
                    message: 'Failed to reset password',
                });
            }
        },
    };
}

module.exports = {
    createAuthController,
};
