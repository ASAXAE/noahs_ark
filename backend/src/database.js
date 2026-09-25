const { Pool } = require('pg');

const {
    createDatabaseConfig,
} = require('./database_config');

const pool = new Pool(
    createDatabaseConfig(),
);

module.exports = pool;
