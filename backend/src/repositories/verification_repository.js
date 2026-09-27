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

async function issueRateLimitedVerificationToken(
    pool,
    userId,
) {
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

        if (
            user === undefined ||
            user.email_verified_at !== null
        ) {
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
        const {
            recent_count,
            daily_count,
        } = limitResult.rows[0];

        if (recent_count >= 1 || daily_count >= 5) {
            await client.query('ROLLBACK');
            return { status: 'rate_limited' };
        }

        const token = await issueEmailVerificationToken(
            client,
            userId,
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

async function deleteUnusedVerificationToken(
    database,
    rawToken,
) {
    await database.query(
        `
            DELETE FROM email_verification_tokens
            WHERE token_hash = $1
                AND consumed_at IS NULL
        `,
        [hashToken(rawToken)],
    );
}

function createVerificationRepository(database) {
    return {
        issueRateLimited(userId) {
            return issueRateLimitedVerificationToken(
                database,
                userId,
            );
        },

        consume(token) {
            return consumeEmailVerificationToken(
                database,
                token,
            );
        },

        deleteUnused(token) {
            return deleteUnusedVerificationToken(
                database,
                token,
            );
        },
    };
}

module.exports = {
    createVerificationRepository,
    deleteUnusedVerificationToken,
    issueEmailVerificationToken,
    consumeEmailVerificationToken,
    issueRateLimitedVerificationToken,
};
