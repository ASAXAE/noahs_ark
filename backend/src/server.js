const express = require('express');
require('dotenv').config();

const pool = require('./database');

const app = express();

const port = process.env.PORT || 3000;

app.use(express.json());

function validateThoughtInput(body = {}) {
    const title =
        typeof body.title === 'string'
            ? body.title.trim()
            : '';

    const content =
        typeof body.content === 'string'
            ? body.content
            : '';

    const tag =
        typeof body.tag === 'string'
            ? body.tag.trim()
            : '';

    const errors = [];

    if (title.length > 50) {
        errors.push('title must not exceed 50 characters');
    }

    if (content.trim().length === 0) {
        errors.push('content is required');
    }

    if (tag.length === 0) {
        errors.push('tag is required');
    }

    if (tag.length > 20) {
        errors.push('tag must not exceed 20 characters');
    }

    return {
        errors,
        value: {
            title,
            content,
            tag,
        },
    };
}

app.get('/health', (request, response) => {
    response.json({
        status: 'ok',
        message: "Noah's Ark API is running",
    });
});

app.get('/thoughts', async (request, response) => {
    try {
        const result = await pool.query(
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
            [1],
        );

        response.json(result.rows);
    } catch (error) {
        console.error('Failed to fetch thoughts:', error.message);

        response.status(500).json({
            message: 'Failed to fetch thoughts',
        });
    }
});

app.get('/database-health', async (request, response) => {
    try {
        const result = await pool.query(
            'SELECT NOW() AS current_time',
        );

        response.json({
            status: 'ok',
            databaseTime: result.rows[0].current_time,
        });
    } catch (error) {
        console.error('Database connection failed:', error.message);

        response.status(500).json({
            status: 'error',
            message: 'Database connection failed',
        });
    }
});

app.post('/thoughts', async (request, response) => {
    const validation = validateThoughtInput(request.body);

    if (validation.errors.length > 0) {
        return response.status(400).json({
            message: 'Invalid thought data',
            errors: validation.errors,
        });
    }

    const thought = validation.value;

    try {
        const result = await pool.query(
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
                1,
                thought.title,
                thought.content,
                thought.tag,
                false,
            ],
        );

        response.status(201).json(result.rows[0]);
    } catch (error) {
        console.error('Failed to create thought:', error.message);

        response.status(500).json({
            message: 'Failed to create thought',
        });
    }
});

app.delete('/thoughts/:id', async (request, response) => {
    const thoughtId = request.params.id;

    if (!/^[1-9]\d*$/.test(thoughtId)) {
        return response.status(400).json({
            message: 'Invalid thought id',
        });
    }

    try {
        const result = await pool.query(
            `
                DELETE FROM thoughts
                WHERE id = $1
                  AND user_id = $2
                RETURNING id
            `,
            [
                thoughtId,
                1,
            ],
        );

        if (result.rowCount === 0) {
            return response.status(404).json({
                message: 'Thought not found',
            });
        }

        return response.status(204).send();
    } catch (error) {
        console.error('Failed to delete thought:', error.message);

        return response.status(500).json({
            message: 'Failed to delete thought',
        });
    }
});

app.listen(port, '0.0.0.0', () => {
    console.log(
        `Noah's Ark API is running on http://localhost:${port}`,
    );
});