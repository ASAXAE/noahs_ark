const path = require('node:path');

require('dotenv').config();

const pool = require('./database');
const { runMigrations } = require('./migration_runner');

async function migrate() {
    let client;

    try {
        client = await pool.connect();

        const migrationsDirectory = path.join(__dirname, '..', 'sql');
        const appliedMigrations = await runMigrations(
            client,
            migrationsDirectory,
        );

        if (appliedMigrations.length === 0) {
            console.log('Database is already up to date.');
            return;
        }

        for (const migrationName of appliedMigrations) {
            console.log(`Applied migration: ${migrationName}`);
        }
    } finally {
        client?.release();
        await pool.end();
    }
}

migrate().catch((error) => {
    console.error('Database migration failed:', error);
    process.exitCode = 1;
});
