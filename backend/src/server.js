const express = require('express');
require('dotenv').config();

const pool = require('./database');

const app = express();

const port = process.env.PORT || 3000;

app.use(express.json());

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
                request.body.title,
                request.body.content,
                request.body.tag,
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

app.listen(port, '0.0.0.0', () => {
    console.log(
        `Noah's Ark API is running on http://localhost:${port}`,
    );
});