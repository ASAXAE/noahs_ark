const express = require('express');
const bcrypt = require('bcryptjs');

require('dotenv').config();

const pool = require('./database');

const {
    validateThoughtInput,
} = require('./thought_validation');

const {
    validateRegistrationInput,
} = require('./auth_validation');

const app = express();

const port = process.env.PORT || 3000;

app.use(express.json());

app.get('/health', (request, response) => {
    response.json({
        status: 'ok',
        message: "Noah's Ark API is running",
    });
});

app.post('/auth/register', async (request, response) => {
    const validation = validateRegistrationInput(request.body);

    if (validation.errors.length > 0) {
        return response.status(400).json({
            message: 'Invalid registration data',
            errors: validation.errors,
        });
    }

    const {
        displayName,
        email,
        password,
    } = validation.value;

    try {
        const passwordHash = await bcrypt.hash(password, 12);

        const result = await pool.query(
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
                    created_at AS "createdAt"
            `,
            [
                displayName,
                email,
                passwordHash,
            ],
        );

        return response.status(201).json(result.rows[0]);
    } catch (error) {
        if (error.code === '23505') {
            return response.status(409).json({
                message: 'Email is already registered',
            });
        }

        console.error('Failed to register user:', error.message);

        return response.status(500).json({
            message: 'Failed to register user',
        });
    }
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

app.patch('/thoughts/:id', async (request, response) => {
    const thoughtId = request.params.id;
    const { title, content, tag, isFavorite = false } = request.body;

    if(!/^[1-9]\d*$/.test(thoughtId)) {
        return response.status(400).json({
            message: 'Invalid thought id',
        });
    }

    const errors = [];

    if (typeof title !== 'string') {
        errors.push('title must be a string');
    }

    if (typeof content !== 'string' || content.trim().length === 0) {
        errors.push('content is required');
    }

    if (typeof tag !== 'string' || tag.trim().length === 0) {
        errors.push('tag is required');
    }

    if (typeof isFavorite !== 'boolean') {
        errors.push('isFavorite must be a boolean');
    }

    if (errors.length > 0) {
        return response.status(400).json({
            message: 'Invalid thought data',
            errors,
        });
    }

    try {
        const result = await pool.query(
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
                title.trim(),
                content.trim(),
                tag.trim(),
                isFavorite,
                thoughtId,
                1,
            ],
        );

        if (result.rows.length === 0) {
            return response.status(404).json({
                message: 'Thought not found',
            });
        }

        return response.json(result.rows[0]);
    } catch (error) {
        console.error('Failed to update thought:', error);

        return response.status(500).json({
            message: 'Failed to update thought',
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
