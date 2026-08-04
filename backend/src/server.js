const express = require('express');
require('dotenv').config();

const pool = require('./database');

const app = express();

const port = process.env.PORT || 3000;

app.use(express.json());

const thoughts = [
    {
        id: 1,
        title: '我的第一条服务器记录',
        content: '这条记录来自 Express。',
        tag: '成长',
        createdAt: new Date().toISOString(),
        updatedAt: new Date().toISOString(),
        isFavorite: false,
    },
];

app.get('/health', (request, response) => {
    response.json({
        status: 'ok',
        message: "Noah's Ark API is running",
    });
});

app.get('/thoughts', (request, response) => {
    response.json(thoughts);
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

app.post('/thoughts', (request, response) => {
    const newThought = {
        id: thoughts.length + 1,
        title: request.body.title,
        content: request.body.content,
        createdAt: new Date().toISOString(),
        updatedAt: new Date().toISOString(),
        tag: request.body.tag,
        isFavorite: false,
    };

    thoughts.push(newThought);

    response.status(201).json(newThought);
});

app.listen(port, '0.0.0.0', () => {
    console.log(
        `Noah's Ark API is running on http://localhost:${port}`,
    );
});