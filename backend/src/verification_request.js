const {
    issueEmailVerificationToken,
} = require('./email_verification');

async function issueRateLimitedVerificationToken(pool, userId) {
    const client = await pool.connect();

    try {
        await client.query('BEGIN');

        const userResult = await client.query(
            `
                SELECT email, email_verified_at
                FROM users
                WHERE id = $1
                FOR UPDATE
            `,
            [userId],
        );
        const user = userResult.rows[0];

        if (user === undefined || user.email_verified_at !== null) {
            await client.query('ROLLBACK');
            return { status: 'unavailable' };
        }

        const limitResult = await client.query(
            `
                SELECT
                    COUNT(*) FILTER (
                        WHERE created_at >
                            clock_timestamp() - INTERVAL '1 minute'
                    )::INTEGER AS recent_count,
                    COUNT(*) FILTER (
                        WHERE created_at >
                            clock_timestamp() - INTERVAL '24 hours'
                    )::INTEGER AS daily_count
                FROM email_verification_tokens
                WHERE user_id = $1
            `,
            [userId],
        );
        const { recent_count, daily_count } = limitResult.rows[0];

        if (recent_count >= 1 || daily_count >= 5) {
            await client.query('ROLLBACK');
            return { status: 'rate_limited' };
        }

        const token = await issueEmailVerificationToken(
            client,
            userId,
        );

        await client.query('COMMIT');
        return { status: 'issued', to: user.email, token };
    } catch (error) {
        await client.query('ROLLBACK');
        throw error;
    } finally {
        client.release();
    }
}

module.exports = {
    issueRateLimitedVerificationToken,
};