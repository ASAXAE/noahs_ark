const crypto = require('node:crypto');
const {
    issueRateLimitedVerificationToken,
} = require('./verification_request');

async function requestVerificationEmail(pool, userId, mailer) {
    if (
        !mailer ||
        typeof mailer.sendVerificationEmail !== 'function'
    ) {
        throw new TypeError('A verification mailer is required');
    }

    const issuance = await issueRateLimitedVerificationToken(
        pool,
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
        const tokenHash = crypto
            .createHash('sha256')
            .update(issuance.token)
            .digest('hex');

        await pool.query(
            `
                DELETE FROM email_verification_tokens
                WHERE token_hash = $1
                    AND consumed_at IS NULL
            `,
            [tokenHash],
        );
        throw error;
    }
}

module.exports = {
    requestVerificationEmail,
};