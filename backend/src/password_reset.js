const crypto = require('node:crypto');

const rawTokenPattern = /^[0-9a-f]{64}$/;

function createRawToken() {
    return crypto.randomBytes(32).toString('hex');
}

function hashToken(rawToken) {
    return crypto
        .createHash('sha256')
        .update(rawToken)
        .digest('hex');
}

function getPasswordResetTokenLifetimeMinutes() {
    const rawValue =
        process.env.PASSWORD_RESET_TOKEN_TTL_MINUTES ?? '60';

    if (!/^[1-9]\d*$/.test(rawValue)) {
        throw new Error(
            'PASSWORD_RESET_TOKEN_TTL_MINUTES must be an integer from 1 to 1440',
        );
    }

    const lifetimeMinutes = Number(rawValue);

    if (
        !Number.isSafeInteger(lifetimeMinutes) ||
        lifetimeMinutes > 1440
    ) {
        throw new Error(
            'PASSWORD_RESET_TOKEN_TTL_MINUTES must be an integer from 1 to 1440',
        );
    }

    return lifetimeMinutes;
}

async function issuePasswordResetToken(database, userId) {
    const rawToken = createRawToken();
    const tokenHash = hashToken(rawToken);
    const lifetimeMinutes =
        getPasswordResetTokenLifetimeMinutes();

    await database.query(
        `
            INSERT INTO password_reset_tokens (
                user_id,
                token_hash,
                expires_at
            )
            VALUES (
                $1,
                $2,
                clock_timestamp()
                    + $3::integer * INTERVAL '1 minute'
            )
        `,
        [
            userId,
            tokenHash,
            lifetimeMinutes,
        ],
    );

    return rawToken;
}

async function resetPasswordWithToken(
    pool,
    rawToken,
    passwordHash,
) {
    if (
        typeof rawToken !== 'string' ||
        !rawTokenPattern.test(rawToken) ||
        typeof passwordHash !== 'string' ||
        passwordHash.length === 0
    ) {
        return false;
    }

    const tokenHash = hashToken(rawToken);
    const client = await pool.connect();

    try {
        await client.query('BEGIN');

        const ownerResult = await client.query(
            `
                SELECT user_id AS "userId"
                FROM password_reset_tokens
                WHERE token_hash = $1
            `,
            [tokenHash],
        );

        if (ownerResult.rowCount !== 1) {
            await client.query('ROLLBACK');
            return false;
        }

        const userId = ownerResult.rows[0].userId;

        const userLockResult = await client.query(
            `
                SELECT id
                FROM users
                WHERE id = $1
                FOR UPDATE
            `,
            [userId],
        );

        if (userLockResult.rowCount !== 1) {
            await client.query('ROLLBACK');
            return false;
        }

        const tokenResult = await client.query(
            `
                UPDATE password_reset_tokens
                SET consumed_at = clock_timestamp()
                WHERE token_hash = $1
                    AND user_id = $2
                    AND consumed_at IS NULL
                    AND expires_at > clock_timestamp()
                RETURNING id
            `,
            [
                tokenHash,
                userId,
            ],
        );

        if (tokenResult.rowCount !== 1) {
            await client.query('ROLLBACK');
            return false;
        }

        await client.query(
            `
                UPDATE users
                SET password_hash = $2
                WHERE id = $1
            `,
            [
                userId,
                passwordHash,
            ],
        );

        await client.query(
            `
                UPDATE password_reset_tokens
                SET consumed_at = COALESCE(
                    consumed_at,
                    clock_timestamp()
                )
                WHERE user_id = $1
                    AND consumed_at IS NULL
            `,
            [userId],
        );

        await client.query(
            `
                UPDATE refresh_tokens
                SET revoked_at = COALESCE(
                    revoked_at,
                    clock_timestamp()
                )
                WHERE user_id = $1
                    AND revoked_at IS NULL
            `,
            [userId],
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
    issuePasswordResetToken,
    resetPasswordWithToken,
};