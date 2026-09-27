const express = require('express');
const helmet = require('helmet');

const pool = require('./database/pool');

const {
    createErrorReporter,
    createOperationalErrorReporter,
    createSecurityEventReporter,
} = require('./observability/error_monitoring');
const {
    createFakeVerificationMailer,
} = require('./mailers/verification_mailer');
const {
    createFakePasswordResetMailer,
} = require('./mailers/password_reset_mailer');

const {
    createHealthRepository,
} = require('./repositories/health_repository');
const {
    createThoughtRepository,
} = require('./repositories/thought_repository');
const {
    createUserRepository,
} = require('./repositories/user_repository');
const {
    createRefreshTokenRepository,
} = require('./repositories/refresh_token_repository');
const {
    createVerificationRepository,
} = require('./repositories/verification_repository');
const {
    createPasswordResetRepository,
} = require('./repositories/password_reset_repository');
const {
    createAccountRepository,
} = require('./repositories/account_repository');

const {
    createHealthService,
} = require('./services/health_service');
const {
    createThoughtService,
} = require('./services/thought_service');
const {
    createAuthService,
} = require('./services/auth_service');
const {
    createVerificationService,
} = require('./services/verification_service');
const {
    createPasswordResetService,
} = require('./services/password_reset_service');

const {
    createHealthController,
} = require('./controllers/health_controller');
const {
    createThoughtController,
} = require('./controllers/thought_controller');
const {
    createAuthController,
} = require('./controllers/auth_controller');

const {
    createHealthRoutes,
} = require('./routes/health_routes');
const {
    createThoughtRoutes,
} = require('./routes/thought_routes');
const {
    createAuthRoutes,
} = require('./routes/auth_routes');

const {
    requireAuthentication,
} = require('./middleware/auth_middleware');
const {
    attachRequestId,
} = require('./middleware/request_context');
const {
    createRequestLogger,
} = require('./middleware/request_logging');
const {
    sensitiveAuthLimiter,
    sessionTokenLimiter,
} = require('./middleware/rate_limiters');
const {
    createErrorHandler,
    notFoundHandler,
} = require('./middleware/error_handlers');

const app = express();

const reportRequestError =
    createErrorReporter();
const reportOperationalError =
    createOperationalErrorReporter();
const reportSecurityEvent =
    createSecurityEventReporter();

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

const healthRepository =
    createHealthRepository(pool);
const thoughtRepository =
    createThoughtRepository(pool);
const userRepository =
    createUserRepository(pool);
const refreshTokenRepository =
    createRefreshTokenRepository(pool);
const verificationRepository =
    createVerificationRepository(pool);
const passwordResetRepository =
    createPasswordResetRepository(pool);
const accountRepository =
    createAccountRepository(pool);

const verificationService =
    createVerificationService({
        verificationRepository,
        mailer: verificationMailer,
    });
const passwordResetService =
    createPasswordResetService({
        passwordResetRepository,
        mailer: passwordResetMailer,
    });

const healthService = createHealthService({
    healthRepository,
});
const thoughtService = createThoughtService({
    thoughtRepository,
});
const authService = createAuthService({
    userRepository,
    refreshTokenRepository,
    accountRepository,
    verificationService,
    passwordResetService,
});

const healthController = createHealthController({
    healthService,
});
const thoughtController = createThoughtController({
    thoughtService,
    reportRequestError,
});
const authController = createAuthController({
    authService,
    reportRequestError,
    reportOperationalError,
    reportSecurityEvent,
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

app.use(createHealthRoutes({
    healthController,
}));
app.use(createAuthRoutes({
    authController,
    requireAuthentication,
}));
app.use(createThoughtRoutes({
    thoughtController,
    requireAuthentication,
}));

app.use(notFoundHandler);
app.use(createErrorHandler({
    reportRequestError,
}));

module.exports = app;
