const express = require('express');
const helmet = require('helmet');
const {
    rateLimit,
} = require('express-rate-limit');

const bcrypt = require('bcryptjs');

require('dotenv').config();

const pool = require('./database');

const {
    createErrorReporter,
    createOperationalErrorReporter,
    createSecurityEventReporter,
} = require('./error_monitoring');

const {
    checkDatabaseReadiness,
} = require('./readiness');

const {
    attachRequestId,
} = require('./request_context');

const {
    createRequestLogger,
} = require('./request_logging');

const {
    createAccessToken,
} = require('./auth_token');

const {
    requireAuthentication,
} = require('./auth_middleware');

const {
    validateThoughtInput,
} = require('./thought_validation');

const {
    validateRegistrationInput,
    validateLoginInput,
    validatePasswordResetRequestInput,
    validatePasswordResetConfirmationInput,
    validateAccountDeletionInput,
} = require('./auth_validation');

const {
    createFakeVerificationMailer,
} = require('./verification_mailer');

const {
    requestVerificationEmail,
} = require('./verification_delivery');
const {
    consumeEmailVerificationToken,
} = require('./email_verification');
const {
    issueRefreshToken,
    rotateRefreshToken,
    revokeRefreshToken,
} = require('./refresh_token');

const {
    createFakePasswordResetMailer,
} = require('./password_reset_mailer');
const {
    requestPasswordResetEmail,
} = require('./password_reset_delivery');
const {
    resetPasswordWithToken,
} = require('./password_reset');
const {
    deleteAccountWithPassword,
} = require('./account_deletion');

const app = express();

const reportRequestError =
    createErrorReporter();
const reportOperationalError =
    createOperationalErrorReporter();
const reportSecurityEvent =
    createSecurityEventReporter();

const port = process.env.PORT || 3000;
const isHstsEnabled =
    process.env.ENABLE_HSTS === 'true';

const isRequestLoggingEnabled =
    process.env.ENABLE_REQUEST_LOGGING === 'true';

const verificationMailer =
    process.env.EMAIL_DELIVERY_MODE === 'fake'
        ? createFakeVerificationMailer()
        : null;

const passwordResetMailer =
    process.env.EMAIL_DELIVERY_MODE === 'fake'
        ? createFakePasswordResetMailer()
        : null;

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

app.use(attachRequestId);

if (isRequestLoggingEnabled) {
    app.use(createRequestLogger());
}

app.use(
    helmet({
        contentSecurityPolicy: false,
        strictTransportSecurity:
            isHstsEnabled
                ? {
                    maxAge: 31536000,
                    includeSubDomains: false,
                }
                : false,
    }),
);

app.use(
    [
        '/auth/register',
        '/auth/login',
        '/auth/account',
        '/auth/email-verification/resend',
        '/auth/email-verification/confirm',
        '/auth/password-reset/request',
        '/auth/password-reset/confirm',
    ],
    sensitiveAuthLimiter,
);

app.use(
    [
        '/auth/token/refresh',
        '/auth/logout',
    ],
    sessionTokenLimiter,
);

app.use(
    express.json({
        limit: '32kb',
    }),
);

app.get('/health', (request, response) => {
    response.set('Cache-Control', 'no-store');

    return response.json({
        status: 'ok',
        message: "Noah's Ark API is running",
    });
});

app.get('/readyz', async (request, response) => {
    const isReady =
        await checkDatabaseReadiness(pool);

    response.set('Cache-Control', 'no-store');

    if (!isReady) {
        return response.status(503).json({
            status: 'unavailable',
        });
    }

    return response.json({
        status: 'ready',
    });
});

app.post('/auth/register', async (request, response) => {
    const validation = validateRegistrationInput(request.body);

    if (validation.errors.length > 0) {
        return response.status(400).json({
            message: 'Invalid registration data',
            errors: validation.errors,
        });
    }

    const {
        displayName,
        email,
        password,
    } = validation.value;

    try {
        const passwordHash = await bcrypt.hash(password, 12);

        const result = await pool.query(
            `
                INSERT INTO users (
                    display_name,
                    email,
                    password_hash
                )
                VALUES ($1, $2, $3)
                RETURNING
                    id,
                    display_name AS "displayName",
                    email,
                    email_verified_at AS "emailVerifiedAt",
                    created_at AS "createdAt"
            `,
            [
                displayName,
                email,
                passwordHash,
            ],
        );

        const user = result.rows[0];

        if (verificationMailer !== null) {
            try {
                await requestVerificationEmail(
                    pool,
                    user.id,
                    verificationMailer,
                );
            } catch {
                reportOperationalError(
                    request,
                    'initial_verification_delivery_failed',
                    201,
                );
            }
        }

        return response.status(201).json(user);
    } catch (error) {
        if (error.code === '23505') {
            return response.status(409).json({
                message: 'Email is already registered',
            });
        }

        reportRequestError(
            request,
            'registration_failed',
        );

        return response.status(500).json({
            message: 'Failed to register user',
        });
    }
});

app.post('/auth/login', async (request, response) => {
    const validation = validateLoginInput(request.body);

    if (validation.errors.length > 0) {
        return response.status(400).json({
            message: 'Invalid login data',
            errors: validation.errors,
        });
    }

    const {
        email,
        password,
    } = validation.value;

    try {
        const result = await pool.query(
            `
                SELECT
                    id,
                    display_name AS "displayName",
                    email,
                    email_verified_at AS "emailVerifiedAt",
                    password_hash AS "passwordHash",
                    created_at AS "createdAt"
                FROM users
                WHERE email = $1
            `,
            [email],
        );

        const user = result.rows[0];

        if (
            user === undefined ||
            typeof user.passwordHash !== 'string'
        ) {
            return response.status(401).json({
                message: 'Invalid email or password',
            });
        }

        const passwordMatches = await bcrypt.compare(
            password,
            user.passwordHash,
        );

        if (!passwordMatches) {
            return response.status(401).json({
                message: 'Invalid email or password',
            });
        }

        const accessToken = createAccessToken(user.id);

        const refreshSession = await issueRefreshToken(
            pool,
            user.id,
        );

        return response.status(200).json({
            accessToken,
            refreshToken: refreshSession.refreshToken,
            refreshTokenExpiresAt: refreshSession.expiresAt,
            user: {
                id: user.id,
                displayName: user.displayName,
                email: user.email,
                emailVerifiedAt: user.emailVerifiedAt,
                createdAt: user.createdAt,
            },
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
});

app.post('/auth/token/refresh', async (request, response) => {
    const refreshToken = request.body?.refreshToken;

    try {
        const result = await rotateRefreshToken(
            pool,
            refreshToken,
        );

        if (result.status !== 'rotated') {
            if (result.status === 'reused') {
                reportSecurityEvent(
                    request,
                    'refresh_token_reuse_detected',
                );
            }

            return response.status(401).json({
                message: 'Invalid or expired refresh token',
            });
        }

        const accessToken =
            createAccessToken(result.userId);

        return response.status(200).json({
            accessToken,
            refreshToken: result.refreshToken,
            refreshTokenExpiresAt: result.expiresAt,
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
});

app.post('/auth/logout', async (request, response) => {
    const refreshToken = request.body?.refreshToken;

    try {
        await revokeRefreshToken(
            pool,
            refreshToken,
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
});

app.get(
    '/auth/me',
    requireAuthentication,
    async (request, response) => {
        try {
            const result = await pool.query(
                `
                    SELECT
                        id,
                        display_name AS "displayName",
                        email,
                        email_verified_at AS "emailVerifiedAt",
                        created_at AS "createdAt"
                    FROM users
                    WHERE id = $1
                `,
                [request.auth.userId],
            );

            const user = result.rows[0];

            if (user === undefined) {
                return response.status(401).json({
                    message: 'User account not found',
                });
            }

            return response.status(200).json(user);
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
);

app.delete(
    '/auth/account',
    requireAuthentication,
    async (request, response) => {
        const validation = validateAccountDeletionInput(
            request.body,
        );

        if (validation.errors.length > 0) {
            return response.status(400).json({
                message: 'Invalid account deletion data',
                errors: validation.errors,
            });
        }

        try {
            const deleted =
                await deleteAccountWithPassword(
                    pool,
                    request.auth.userId,
                    validation.value.password,
                );

            if (!deleted) {
                return response.status(403).json({
                    message: 'Current password is incorrect',
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
);

app.post(
    '/auth/email-verification/resend',
    requireAuthentication,
    async (request, response) => {
        if (verificationMailer === null) {
            return response.status(503).json({
                message: 'Email delivery is not configured',
            });
        }

        try {
            const result = await requestVerificationEmail(
                pool,
                request.auth.userId,
                verificationMailer,
            );

            if (result.status === 'rate_limited') {
                return response.status(429).json({
                    message: 'Please wait before requesting another verification email',
                });
            }

            return response.status(202).json({
                message: 'Verification request accepted',
            });
        } catch {
            reportRequestError(
                request,
                'verification_request_failed',
                503,
            );

            return response.status(503).json({
                message: 'Verification email is temporarily unavailable',
            });
        }
    },
);

app.post(
    '/auth/email-verification/confirm',
    async (request, response) => {
        const token = request.body?.token;

        try {
            const verified = await consumeEmailVerificationToken(
                pool,
                token,
            );

            if (!verified) {
                return response.status(400).json({
                    message: 'Invalid or expired verification token',
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
                message: 'Failed to confirm email verification',
            });
        }
    },
);

app.post(
    '/auth/password-reset/request',
    async (request, response) => {
        const validation =
            validatePasswordResetRequestInput(
                request.body,
            );

        if (validation.errors.length > 0) {
            return response.status(400).json({
                message: 'Invalid password reset request',
                errors: validation.errors,
            });
        }

        if (passwordResetMailer === null) {
            return response.status(503).json({
                message: 'Email delivery is not configured',
            });
        }

        try {
            await requestPasswordResetEmail(
                pool,
                validation.value.email,
                passwordResetMailer,
            );
        } catch {
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
);

app.post(
    '/auth/password-reset/confirm',
    async (request, response) => {
        const validation =
            validatePasswordResetConfirmationInput(
                request.body,
            );

        if (validation.errors.length > 0) {
            return response.status(400).json({
                message: 'Invalid password reset data',
                errors: validation.errors,
            });
        }

        const {
            token,
            password,
        } = validation.value;

        try {
            const passwordHash = await bcrypt.hash(
                password,
                12,
            );

            const reset = await resetPasswordWithToken(
                pool,
                token,
                passwordHash,
            );

            if (!reset) {
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
);

app.get(
    '/thoughts',
    requireAuthentication,
    async (request, response) => {
    try {
        const result = await pool.query(
            `
                SELECT
                    id,
                    title,
                    content,
                    tag,
                    is_favorite AS "isFavorite",
                    created_at AS "createdAt",
                    updated_at AS "updatedAt"
                FROM thoughts
                WHERE user_id = $1
                ORDER BY created_at DESC
            `,
            [request.auth.userId],
        );

        response.json(result.rows);
    } catch {
        reportRequestError(
            request,
            'thought_list_failed',
        );

        response.status(500).json({
            message: 'Failed to fetch thoughts',
        });
    }
    },
);

app.post(
    '/thoughts',
    requireAuthentication,
    async (request, response) => {
    const validation = validateThoughtInput(request.body);

    if (validation.errors.length > 0) {
        return response.status(400).json({
            message: 'Invalid thought data',
            errors: validation.errors,
        });
    }

    const thought = validation.value;

    try {
        const result = await pool.query(
            `
                INSERT INTO thoughts (
                    user_id,
                    title,
                    content,
                    tag,
                    is_favorite
                )
                VALUES ($1, $2, $3, $4, $5)
                RETURNING
                    id,
                    title,
                    content,
                    tag,
                    is_favorite AS "isFavorite",
                    created_at AS "createdAt",
                    updated_at AS "updatedAt"
            `,
            [
                request.auth.userId,
                thought.title,
                thought.content,
                thought.tag,
                false,
            ],
        );

        response.status(201).json(result.rows[0]);
    } catch {
        reportRequestError(
            request,
            'thought_creation_failed',
        );

        response.status(500).json({
            message: 'Failed to create thought',
        });
    }
    },
);

app.patch(
    '/thoughts/:id',
    requireAuthentication,
    async (request, response) => {
    const thoughtId = request.params.id;
    const { title, content, tag, isFavorite = false } = request.body;

    if(!/^[1-9]\d*$/.test(thoughtId)) {
        return response.status(400).json({
            message: 'Invalid thought id',
        });
    }

    const errors = [];

    if (typeof title !== 'string') {
        errors.push('title must be a string');
    }

    if (typeof content !== 'string' || content.trim().length === 0) {
        errors.push('content is required');
    }

    if (typeof tag !== 'string' || tag.trim().length === 0) {
        errors.push('tag is required');
    }

    if (typeof isFavorite !== 'boolean') {
        errors.push('isFavorite must be a boolean');
    }

    if (errors.length > 0) {
        return response.status(400).json({
            message: 'Invalid thought data',
            errors,
        });
    }

    try {
        const result = await pool.query(
        `
            UPDATE thoughts
            SET
                title = $1,
                content = $2,
                tag = $3,
                is_favorite = $4,
                updated_at = NOW()
            WHERE id = $5
                AND user_id = $6
            RETURNING
                id,
                title,
                content,
                tag,
                is_favorite AS "isFavorite",
                created_at AS "createdAt",
                updated_at AS "updatedAt"
            `,
            [
                title.trim(),
                content.trim(),
                tag.trim(),
                isFavorite,
                thoughtId,
                request.auth.userId,
            ],
        );

        if (result.rows.length === 0) {
            return response.status(404).json({
                message: 'Thought not found',
            });
        }

        return response.json(result.rows[0]);
    } catch {
        reportRequestError(
            request,
            'thought_update_failed',
        );

        return response.status(500).json({
            message: 'Failed to update thought',
        });
    }
    },
);

app.delete(
    '/thoughts/:id',
    requireAuthentication,
    async (request, response) => {
    const thoughtId = request.params.id;

    if (!/^[1-9]\d*$/.test(thoughtId)) {
        return response.status(400).json({
            message: 'Invalid thought id',
        });
    }

    try {
        const result = await pool.query(
            `
                DELETE FROM thoughts
                WHERE id = $1
                  AND user_id = $2
                RETURNING id
            `,
            [
                thoughtId,
                request.auth.userId,
            ],
        );

        if (result.rowCount === 0) {
            return response.status(404).json({
                message: 'Thought not found',
            });
        }

        return response.status(204).send();
    } catch {
        reportRequestError(
            request,
            'thought_deletion_failed',
        );

        return response.status(500).json({
            message: 'Failed to delete thought',
        });
    }
    },
);

app.use((request, response) => {
    return response.status(404).json({
        message: 'Route not found',
    });
});

app.use((error, request, response, next) => {
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
});

if (require.main === module) {
    app.listen(port, '0.0.0.0', () => {
        console.log(
            `Noah's Ark API is running on http://localhost:${port}`,
        );
    });
}

module.exports = app;
