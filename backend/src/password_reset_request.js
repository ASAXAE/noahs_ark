const {
    issuePasswordResetToken,
} = require('./password_reset');

async function issueRateLimitedPasswordResetToken(
    pool,
    email,
) {
    const normalizedEmail =
        typeof email === 'string'
            ? email.trim().toLowerCase()
            : '';

    if (normalizedEmail.length === 0) {
        return { status: 'accepted' };
    }

    const client = await pool.connect();

    try {
        await client.query('BEGIN');

        const userResult = await client.query(
            `
                SELECT id, email
                FROM users
                WHERE email = $1
                FOR UPDATE
            `,
            [normalizedEmail],
        );

        const user = userResult.rows[0];

        if (user === undefined) {
            await client.query('ROLLBACK');
            return { status: 'accepted' };
        }

        const limitResult = await client.query(
            `
                SELECT
                    COUNT(*) FILTER (
                        WHERE created_at >
                            clock_timestamp()
                            - INTERVAL '1 minute'
                    )::INTEGER AS recent_count,
                    COUNT(*) FILTER (
                        WHERE created_at >
                            clock_timestamp()
                            - INTERVAL '24 hours'
                    )::INTEGER AS daily_count
                FROM password_reset_tokens
                WHERE user_id = $1
            `,
            [user.id],
        );

        const {
            recent_count,
            daily_count,
        } = limitResult.rows[0];

        if (recent_count >= 1 || daily_count >= 5) {
            await client.query('ROLLBACK');
            return { status: 'accepted' };
        }

        const token = await issuePasswordResetToken(
            client,
            user.id,
        );

        await client.query('COMMIT');

        return {
            status: 'issued',
            to: user.email,
            token,
        };
    } catch (error) {
        await client.query('ROLLBACK');
        throw error;
    } finally {
        client.release();
    }
}

module.exports = {
    issueRateLimitedPasswordResetToken,
};