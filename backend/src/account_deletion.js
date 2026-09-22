const bcrypt = require('bcryptjs');

async function deleteAccountWithPassword(
    pool,
    userId,
    password,
) {
    if (
        typeof userId !== 'string' ||
        !/^[1-9]\d*$/.test(userId) ||
        typeof password !== 'string' ||
        password.length === 0 ||
        password.length > 72
    ) {
        return false;
    }

    const client = await pool.connect();

    try {
        await client.query('BEGIN');

        const userResult = await client.query(
            `
                SELECT
                    password_hash AS "passwordHash"
                FROM users
                WHERE id = $1
                FOR UPDATE
            `,
            [userId],
        );

        if (
            userResult.rowCount !== 1 ||
            typeof userResult.rows[0].passwordHash !== 'string'
        ) {
            await client.query('ROLLBACK');
            return false;
        }

        const passwordMatches = await bcrypt.compare(
            password,
            userResult.rows[0].passwordHash,
        );

        if (!passwordMatches) {
            await client.query('ROLLBACK');
            return false;
        }

        const deletionResult = await client.query(
            `
                DELETE FROM users
                WHERE id = $1
                RETURNING id
            `,
            [userId],
        );

        if (deletionResult.rowCount !== 1) {
            await client.query('ROLLBACK');
            return false;
        }

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
    deleteAccountWithPassword,
};