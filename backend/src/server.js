require('dotenv').config();

const app = require('./app');

const port = process.env.PORT || 3000;

if (require.main === module) {
    app.listen(port, '0.0.0.0', () => {
        console.log(
            `Noah's Ark API is running on http://localhost:${port}`,
        );
    });
}

module.exports = app;
