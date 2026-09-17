const crypto = require('node:crypto');

function hashToken(rawToken) {
    return crypto.createHash('sha256').update(rawToken).digest('hex');
}

async function issueEmailVerificationToken(pool, userId) {
    const rawToken = crypto.randomBytes(32).toString('hex');
    const tokenHash = hashToken(rawToken);

    await pool.query(
        `
            INSERT INTO email_verification_tokens (
                user_id, token_hash, expires_at
            )
            VALUES ($1, $2, NOW() + INTERVAL '24 hours')
        `,
        [userId, tokenHash],
    );

    return rawToken;
}

async function consumeEmailVerificationToken(pool, rawToken) {
    if (typeof rawToken !== 'string' || !/^[0-9a-f]{64}$/.test(rawToken)) {
        return false;
    }

    const client = await pool.connect();

    try {
        await client.query('BEGIN');

        const result = await client.query(
            `
                UPDATE email_verification_tokens
                SET consumed_at = clock_timestamp()
                WHERE token_hash = $1
                    AND consumed_at IS NULL
                    AND expires_at > clock_timestamp()
                RETURNING user_id
            `,
            [hashToken(rawToken)],
        );

        if (result.rowCount !== 1) {
            await client.query('ROLLBACK');
            return false;
        }

        await client.query(
            `
                UPDATE users
                SET email_verified_at =
                    COALESCE(email_verified_at, clock_timestamp())
                WHERE id = $1
            `,
            [result.rows[0].user_id],
        );

        await client.query('COMMIT');
        return true;
    } catch (error) {
        await client.query('ROLLBACK');
        throw error;
    } finally {
        client.release();
    }
}

module.exports = {
    issueEmailVerificationToken,
    consumeEmailVerificationToken,
};
