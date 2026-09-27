const {
    createVerificationRepository,
} = require('../repositories/verification_repository');

async function deliverVerificationEmail(
    verificationRepository,
    userId,
    mailer,
) {
    if (
        !mailer ||
        typeof mailer.sendVerificationEmail !== 'function'
    ) {
        throw new TypeError('A verification mailer is required');
    }

    const issuance =
        await verificationRepository.issueRateLimited(
            userId,
        );

    if (issuance.status !== 'issued') {
        return { status: issuance.status };
    }

    try {
        await mailer.sendVerificationEmail({
            to: issuance.to,
            token: issuance.token,
        });
        return { status: 'sent' };
    } catch (error) {
        await verificationRepository.deleteUnused(
            issuance.token,
        );
        throw error;
    }
}

async function requestVerificationEmail(pool, userId, mailer) {
    return deliverVerificationEmail(
        createVerificationRepository(pool),
        userId,
        mailer,
    );
}

function createVerificationService({
    verificationRepository,
    mailer,
}) {
    return {
        isConfigured() {
            return mailer !== null;
        },

        request(userId) {
            return deliverVerificationEmail(
                verificationRepository,
                userId,
                mailer,
            );
        },

        consume(token) {
            return verificationRepository.consume(token);
        },
    };
}

module.exports = {
    createVerificationService,
    requestVerificationEmail,
};
