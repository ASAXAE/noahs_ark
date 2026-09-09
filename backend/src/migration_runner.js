const crypto = require('node:crypto');
const fs = require('node:fs/promises');
const path = require('node:path');

const migrationFilePattern = /^(\d{3})_[a-z0-9_]+\.sql$/;

async function loadMigrations(migrationsDirectory) {
    const entries = await fs.readdir(migrationsDirectory, {
        withFileTypes: true,
    });

    const migrations = [];

    for (const entry of entries) {
        if (!entry.isFile() || !entry.name.endsWith('.sql')) {
            continue;
        }

        const match = migrationFilePattern.exec(entry.name);

        if (match === null) {
            throw new Error(`Invalid migration filename: ${entry.name}`);
        }

        const sql = await fs.readFile(
            path.join(migrationsDirectory, entry.name),
            'utf8',
        );

        migrations.push({
            version: Number(match[1]),
            name: entry.name,
            checksum: crypto.createHash('sha256').update(sql).digest('hex'),
            sql,
        });
    }

    migrations.sort((left, right) => left.version - right.version);

    for (let index = 1; index < migrations.length; index += 1) {
        if (migrations[index - 1].version === migrations[index].version) {
            throw new Error(
                `Duplicate migration version: ${migrations[index].version}`,
            );
        }
    }

    return migrations;
}

async function runMigrations(client, migrationsDirectory) {
    const migrations = await loadMigrations(migrationsDirectory);

    await client.query(`
        CREATE TABLE IF NOT EXISTS schema_migrations (
            version INTEGER PRIMARY KEY,
            name TEXT NOT NULL,
            checksum CHAR(64) NOT NULL,
            applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
        )
    `);

    const result = await client.query(`
        SELECT version, name, checksum
        FROM schema_migrations
        ORDER BY version
    `);

    const appliedByVersion = new Map(
        result.rows.map((row) => [Number(row.version), row]),
    );

    const newlyApplied = [];

    for (const migration of migrations) {
        const applied = appliedByVersion.get(migration.version);

        if (applied !== undefined) {
            if (
                applied.name !== migration.name ||
                applied.checksum !== migration.checksum
            ) {
                throw new Error(
                    `Applied migration ${migration.version} no longer matches its file`,
                );
            }

            continue;
        }

        await client.query('BEGIN');

        try {
            await client.query(migration.sql);
            await client.query(
                `
                    INSERT INTO schema_migrations (version, name, checksum)
                    VALUES ($1, $2, $3)
                `,
                [migration.version, migration.name, migration.checksum],
            );
            await client.query('COMMIT');
            newlyApplied.push(migration.name);
        } catch (error) {
            await client.query('ROLLBACK');

            throw new Error(
                `Migration ${migration.name} failed`,
                { cause: error },
            );
        }
    }

    return newlyApplied;
}

module.exports = {
    loadMigrations,
    runMigrations,
};