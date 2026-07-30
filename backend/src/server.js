const express = require('express');
require('dotenv').config();

const app = express();

const port = process.env.PORT || 3000;

app.use(express.json());

app.get('/health', (request, response) => {
    response.json({
        status: 'ok',
        message: "Noah's Ark API is running",
    });
});

app.listen(port, '0.0.0.0', () => {
    console.log(
        `Noah's Ark API is running on http://localhost:${port}`,
    );
});