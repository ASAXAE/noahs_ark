function createThoughtRepository(database) {
    return {
        async listForUser(userId) {
            const result = await database.query(
                `
                    SELECT
                        id,
                        title,
                        content,
                        tag,
                        is_favorite AS "isFavorite",
                        created_at AS "createdAt",
                        updated_at AS "updatedAt"
                    FROM thoughts
                    WHERE user_id = $1
                    ORDER BY created_at DESC
                `,
                [userId],
            );

            return result.rows;
        },

        async createForUser(userId, thought) {
            const result = await database.query(
                `
                    INSERT INTO thoughts (
                        user_id,
                        title,
                        content,
                        tag,
                        is_favorite
                    )
                    VALUES ($1, $2, $3, $4, $5)
                    RETURNING
                        id,
                        title,
                        content,
                        tag,
                        is_favorite AS "isFavorite",
                        created_at AS "createdAt",
                        updated_at AS "updatedAt"
                `,
                [
                    userId,
                    thought.title,
                    thought.content,
                    thought.tag,
                    false,
                ],
            );

            return result.rows[0];
        },

        async updateForUser(
            userId,
            thoughtId,
            thought,
        ) {
            const result = await database.query(
                `
                    UPDATE thoughts
                    SET
                        title = $1,
                        content = $2,
                        tag = $3,
                        is_favorite = $4,
                        updated_at = NOW()
                    WHERE id = $5
                        AND user_id = $6
                    RETURNING
                        id,
                        title,
                        content,
                        tag,
                        is_favorite AS "isFavorite",
                        created_at AS "createdAt",
                        updated_at AS "updatedAt"
                `,
                [
                    thought.title,
                    thought.content,
                    thought.tag,
                    thought.isFavorite,
                    thoughtId,
                    userId,
                ],
            );

            return result.rows[0];
        },

        async deleteForUser(userId, thoughtId) {
            const result = await database.query(
                `
                    DELETE FROM thoughts
                    WHERE id = $1
                      AND user_id = $2
                    RETURNING id
                `,
                [
                    thoughtId,
                    userId,
                ],
            );

            return result.rowCount > 0;
        },
    };
}

module.exports = {
    createThoughtRepository,
};
