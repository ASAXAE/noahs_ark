const {
    createPasswordResetRepository,
} = require('../repositories/password_reset_repository');

async function deliverPasswordResetEmail(
    passwordResetRepository,
    email,
    mailer,
) {
    if (
        !mailer ||
        typeof mailer.sendPasswordResetEmail !== 'function'
    ) {
        throw new TypeError(
            'A password reset mailer is required',
        );
    }

    const issuance =
        await passwordResetRepository.issueRateLimited(
            email,
        );

    if (issuance.status !== 'issued') {
        return { status: 'accepted' };
    }

    try {
        await mailer.sendPasswordResetEmail({
            to: issuance.to,
            token: issuance.token,
        });

        return { status: 'accepted' };
    } catch (error) {
        await passwordResetRepository.deleteUnused(
            issuance.token,
        );
        throw error;
    }
}

async function requestPasswordResetEmail(
    pool,
    email,
    mailer,
) {
    return deliverPasswordResetEmail(
        createPasswordResetRepository(pool),
        email,
        mailer,
    );
}

function createPasswordResetService({
    passwordResetRepository,
    mailer,
}) {
    return {
        isConfigured() {
            return mailer !== null;
        },

        request(email) {
            return deliverPasswordResetEmail(
                passwordResetRepository,
                email,
                mailer,
            );
        },

        reset(token, passwordHash) {
            return passwordResetRepository.reset(
                token,
                passwordHash,
            );
        },
    };
}

module.exports = {
    createPasswordResetService,
    requestPasswordResetEmail,
};
