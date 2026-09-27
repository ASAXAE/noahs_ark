function createUserRepository(database) {
    return {
        async createUser({
            displayName,
            email,
            passwordHash,
        }) {
            const result = await database.query(
                `
                    INSERT INTO users (
                        display_name,
                        email,
                        password_hash
                    )
                    VALUES ($1, $2, $3)
                    RETURNING
                        id,
                        display_name AS "displayName",
                        email,
                        email_verified_at AS "emailVerifiedAt",
                        created_at AS "createdAt"
                `,
                [
                    displayName,
                    email,
                    passwordHash,
                ],
            );

            return result.rows[0];
        },

        async findUserByEmailWithPassword(email) {
            const result = await database.query(
                `
                    SELECT
                        id,
                        display_name AS "displayName",
                        email,
                        email_verified_at AS "emailVerifiedAt",
                        password_hash AS "passwordHash",
                        created_at AS "createdAt"
                    FROM users
                    WHERE email = $1
                `,
                [email],
            );

            return result.rows[0];
        },

        async findUserById(userId) {
            const result = await database.query(
                `
                    SELECT
                        id,
                        display_name AS "displayName",
                        email,
                        email_verified_at AS "emailVerifiedAt",
                        created_at AS "createdAt"
                    FROM users
                    WHERE id = $1
                `,
                [userId],
            );

            return result.rows[0];
        },
    };
}

module.exports = {
    createUserRepository,
};
