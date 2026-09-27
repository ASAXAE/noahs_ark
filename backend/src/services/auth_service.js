const bcrypt = require('bcryptjs');

const {
    createAccessToken,
} = require('./auth_token_service');
const {
    validateRegistrationInput,
    validateLoginInput,
    validatePasswordResetRequestInput,
    validatePasswordResetConfirmationInput,
    validateAccountDeletionInput,
} = require('../validators/auth_validation');
function createAuthService({
    userRepository,
    refreshTokenRepository,
    accountRepository,
    verificationService,
    passwordResetService,
}) {
    return {
        async register(input) {
            const validation =
                validateRegistrationInput(input);

            if (validation.errors.length > 0) {
                return {
                    status: 'invalid',
                    errors: validation.errors,
                };
            }

            const {
                displayName,
                email,
                password,
            } = validation.value;

            try {
                const passwordHash = await bcrypt.hash(
                    password,
                    12,
                );
                const user =
                    await userRepository.createUser({
                        displayName,
                        email,
                        passwordHash,
                    });

                let deliveryFailed = false;

                if (verificationService.isConfigured()) {
                    try {
                        await verificationService.request(
                            user.id,
                        );
                    } catch {
                        deliveryFailed = true;
                    }
                }

                return {
                    status: 'created',
                    user,
                    deliveryFailed,
                };
            } catch (error) {
                if (error.code === '23505') {
                    return {
                        status: 'conflict',
                    };
                }

                throw error;
            }
        },

        async login(input) {
            const validation =
                validateLoginInput(input);

            if (validation.errors.length > 0) {
                return {
                    status: 'invalid',
                    errors: validation.errors,
                };
            }

            const {
                email,
                password,
            } = validation.value;
            const user =
                await userRepository
                    .findUserByEmailWithPassword(email);

            if (
                user === undefined ||
                typeof user.passwordHash !== 'string'
            ) {
                return {
                    status: 'unauthorized',
                };
            }

            const passwordMatches =
                await bcrypt.compare(
                    password,
                    user.passwordHash,
                );

            if (!passwordMatches) {
                return {
                    status: 'unauthorized',
                };
            }

            const accessToken =
                createAccessToken(user.id);
            const refreshSession =
                await refreshTokenRepository.issue(
                    user.id,
                );

            return {
                status: 'authenticated',
                accessToken,
                refreshToken:
                    refreshSession.refreshToken,
                refreshTokenExpiresAt:
                    refreshSession.expiresAt,
                user: {
                    id: user.id,
                    displayName: user.displayName,
                    email: user.email,
                    emailVerifiedAt:
                        user.emailVerifiedAt,
                    createdAt: user.createdAt,
                },
            };
        },

        async refreshSession(refreshToken) {
            const result = await refreshTokenRepository.rotate(
                refreshToken,
            );

            if (result.status !== 'rotated') {
                return result;
            }

            return {
                status: 'rotated',
                accessToken:
                    createAccessToken(result.userId),
                refreshToken: result.refreshToken,
                refreshTokenExpiresAt: result.expiresAt,
            };
        },

        async logout(refreshToken) {
            await refreshTokenRepository.revoke(
                refreshToken,
            );
        },

        async getCurrentUser(userId) {
            const user =
                await userRepository.findUserById(userId);

            return user === undefined
                ? {
                    status: 'not_found',
                }
                : {
                    status: 'found',
                    user,
                };
        },

        async deleteAccount(userId, input) {
            const validation =
                validateAccountDeletionInput(input);

            if (validation.errors.length > 0) {
                return {
                    status: 'invalid',
                    errors: validation.errors,
                };
            }

            const deleted =
                await accountRepository.deleteWithPassword(
                    userId,
                    validation.value.password,
                );

            return {
                status: deleted
                    ? 'deleted'
                    : 'incorrect_password',
            };
        },

        async requestVerification(userId) {
            if (!verificationService.isConfigured()) {
                return {
                    status: 'not_configured',
                };
            }

            const result = await verificationService.request(
                userId,
            );

            return result.status === 'rate_limited'
                ? {
                    status: 'rate_limited',
                }
                : {
                    status: 'accepted',
                };
        },

        async confirmVerification(token) {
            const verified =
                await verificationService.consume(
                    token,
                );

            return {
                status: verified
                    ? 'verified'
                    : 'invalid',
            };
        },

        async requestPasswordReset(input) {
            const validation =
                validatePasswordResetRequestInput(input);

            if (validation.errors.length > 0) {
                return {
                    status: 'invalid',
                    errors: validation.errors,
                };
            }

            if (!passwordResetService.isConfigured()) {
                return {
                    status: 'not_configured',
                };
            }

            let deliveryFailed = false;

            try {
                await passwordResetService.request(
                    validation.value.email,
                );
            } catch {
                deliveryFailed = true;
            }

            return {
                status: 'accepted',
                deliveryFailed,
            };
        },

        async confirmPasswordReset(input) {
            const validation =
                validatePasswordResetConfirmationInput(
                    input,
                );

            if (validation.errors.length > 0) {
                return {
                    status: 'invalid_input',
                    errors: validation.errors,
                };
            }

            const passwordHash = await bcrypt.hash(
                validation.value.password,
                12,
            );
            const reset = await passwordResetService.reset(
                validation.value.token,
                passwordHash,
            );

            return {
                status: reset
                    ? 'reset'
                    : 'invalid_token',
            };
        },
    };
}

module.exports = {
    createAuthService,
};
