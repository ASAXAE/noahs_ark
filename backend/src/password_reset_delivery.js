const crypto = require('node:crypto');

const {
    issueRateLimitedPasswordResetToken,
} = require('./password_reset_request');

async function requestPasswordResetEmail(
    pool,
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
        await issueRateLimitedPasswordResetToken(
            pool,
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
        const tokenHash = crypto
            .createHash('sha256')
            .update(issuance.token)
            .digest('hex');

        await pool.query(
            `
                DELETE FROM password_reset_tokens
                WHERE token_hash = $1
                    AND consumed_at IS NULL
            `,
            [tokenHash],
        );

        throw error;
    }
}

module.exports = {
    requestPasswordResetEmail,
};