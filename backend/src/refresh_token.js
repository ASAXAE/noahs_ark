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

function getRefreshTokenLifetimeDays() {
    const rawValue =
        process.env.REFRESH_TOKEN_TTL_DAYS ?? '30';

    if (!/^[1-9]\d*$/.test(rawValue)) {
        throw new Error(
            'REFRESH_TOKEN_TTL_DAYS must be an integer from 1 to 365',
        );
    }

    const lifetimeDays = Number(rawValue);

    if (
        !Number.isSafeInteger(lifetimeDays) ||
        lifetimeDays > 365
    ) {
        throw new Error(
            'REFRESH_TOKEN_TTL_DAYS must be an integer from 1 to 365',
        );
    }

    return lifetimeDays;
}

async function issueRefreshToken(pool, userId) {
    const rawToken = createRawToken();
    const tokenHash = hashToken(rawToken);
    const familyId = crypto.randomUUID();
    const lifetimeDays = getRefreshTokenLifetimeDays();

    const result = await pool.query(
        `
            INSERT INTO refresh_tokens (
                user_id,
                family_id,
                token_hash,
                expires_at
            )
            VALUES (
                $1,
                $2,
                $3,
                clock_timestamp()
                    + $4::integer * INTERVAL '1 day'
            )
            RETURNING expires_at AS "expiresAt"
        `,
        [
            userId,
            familyId,
            tokenHash,
            lifetimeDays,
        ],
    );

    return {
        refreshToken: rawToken,
        expiresAt: result.rows[0].expiresAt,
    };
}

async function rotateRefreshToken(pool, rawToken) {
    if (
        typeof rawToken !== 'string' ||
        !rawTokenPattern.test(rawToken)
    ) {
        return { status: 'invalid' };
    }

    const tokenHash = hashToken(rawToken);
    const client = await pool.connect();

    try {
        await client.query('BEGIN');

        const ownerResult = await client.query(
            `
                SELECT user_id AS "userId"
                FROM refresh_tokens
                WHERE token_hash = $1
            `,
            [tokenHash],
        );

        if (ownerResult.rowCount !== 1) {
            await client.query('ROLLBACK');
            return { status: 'invalid' };
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
            return { status: 'invalid' };
        }

        const tokenResult = await client.query(
            `
                SELECT
                    id,
                    user_id AS "userId",
                    family_id AS "familyId",
                    expires_at AS "expiresAt",
                    rotated_at AS "rotatedAt",
                    revoked_at AS "revokedAt",
                    expires_at <= clock_timestamp()
                        AS "isExpired"
                FROM refresh_tokens
                WHERE token_hash = $1
                FOR UPDATE
            `,
            [tokenHash],
        );

        if (tokenResult.rowCount !== 1) {
            await client.query('ROLLBACK');
            return { status: 'invalid' };
        }

        const token = tokenResult.rows[0];

        if (token.revokedAt !== null) {
            await client.query('ROLLBACK');
            return { status: 'invalid' };
        }

        if (token.rotatedAt !== null) {
            await client.query(
                `
                    UPDATE refresh_tokens
                    SET revoked_at = COALESCE(
                        revoked_at,
                        clock_timestamp()
                    )
                    WHERE family_id = $1
                `,
                [token.familyId],
            );

            await client.query('COMMIT');

            return { status: 'reused' };
        }

        if (token.isExpired) {
            await client.query('ROLLBACK');
            return { status: 'invalid' };
        }

        const replacementRawToken = createRawToken();
        const replacementHash =
            hashToken(replacementRawToken);

        const replacementResult = await client.query(
            `
                INSERT INTO refresh_tokens (
                    user_id,
                    family_id,
                    token_hash,
                    expires_at
                )
                SELECT
                    $1,
                    $2,
                    $3,
                    $4::timestamptz
                WHERE $4::timestamptz
                    > clock_timestamp()
                RETURNING id
            `,
            [
                token.userId,
                token.familyId,
                replacementHash,
                token.expiresAt,
            ],
        );

        if (replacementResult.rowCount !== 1) {
            await client.query('ROLLBACK');
            return { status: 'invalid' };
        }

        await client.query(
            `
                UPDATE refresh_tokens
                SET
                    rotated_at = clock_timestamp(),
                    replaced_by_token_id = $2
                WHERE id = $1
            `,
            [
                token.id,
                replacementResult.rows[0].id,
            ],
        );

        await client.query('COMMIT');

        return {
            status: 'rotated',
            userId: token.userId,
            refreshToken: replacementRawToken,
            expiresAt: token.expiresAt,
        };
    } catch (error) {
        await client.query('ROLLBACK');
        throw error;
    } finally {
        client.release();
    }
}

async function revokeRefreshToken(pool, rawToken) {
    if (
        typeof rawToken !== 'string' ||
        !rawTokenPattern.test(rawToken)
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
                FROM refresh_tokens
                WHERE token_hash = $1
            `,
            [tokenHash],
        );

        if (ownerResult.rowCount !== 1) {
            await client.query('ROLLBACK');
            return false;
        }

        const userLockResult = await client.query(
            `
                SELECT id
                FROM users
                WHERE id = $1
                FOR UPDATE
            `,
            [ownerResult.rows[0].userId],
        );

        if (userLockResult.rowCount !== 1) {
            await client.query('ROLLBACK');
            return false;
        }

        const result = await client.query(
            `
                UPDATE refresh_tokens
                SET revoked_at = COALESCE(
                    revoked_at,
                    clock_timestamp()
                )
                WHERE family_id = (
                    SELECT family_id
                    FROM refresh_tokens
                    WHERE token_hash = $1
                )
            `,
            [tokenHash],
        );

        await client.query('COMMIT');

        return result.rowCount > 0;
    } catch (error) {
        await client.query('ROLLBACK');
        throw error;
    } finally {
        client.release();
    }
}

module.exports = {
    issueRefreshToken,
    rotateRefreshToken,
    revokeRefreshToken,
};