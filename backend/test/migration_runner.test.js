const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const {
    afterEach,
    beforeEach,
    test,
} = require('node:test');

const {
    loadMigrations,
    runMigrations,
} = require('../src/migration_runner');

let migrationsDirectory;

beforeEach(async () => {
    migrationsDirectory = await fs.mkdtemp(
        path.join(os.tmpdir(), 'noahs-ark-migrations-'),
    );
});

afterEach(async () => {
    await fs.rm(migrationsDirectory, {
        recursive: true,
        force: true,
    });
});

async function writeMigration(name, sql) {
    await fs.writeFile(
        path.join(migrationsDirectory, name),
        sql,
        'utf8',
    );
}

function createClient({
    appliedRows = [],
    failOnSql = null,
} = {}) {
    const calls = [];

    return {
        calls,

        async query(text, values) {
            const sql = text.trim();

            calls.push({ sql, values });

            if (sql.startsWith('SELECT version, name, checksum')) {
                return { rows: appliedRows };
            }

            if (sql === failOnSql) {
                throw new Error('Simulated migration failure');
            }

            return { rows: [] };
        },
    };
}

test('loads migrations in version order with checksums', async () => {
    await writeMigration('002_second.sql', 'SELECT 2;');
    await writeMigration('001_first.sql', 'SELECT 1;');

    const migrations = await loadMigrations(migrationsDirectory);

    assert.deepEqual(
        migrations.map(({ version, name }) => ({ version, name })),
        [
            { version: 1, name: '001_first.sql' },
            { version: 2, name: '002_second.sql' },
        ],
    );

    assert.equal(
        migrations[0].checksum,
        crypto
            .createHash('sha256')
            .update('SELECT 1;')
            .digest('hex'),
    );
});

test('rejects an invalid migration filename', async () => {
    await writeMigration('first-migration.sql', 'SELECT 1;');

    await assert.rejects(
        () => loadMigrations(migrationsDirectory),
        /Invalid migration filename/,
    );
});

test('rejects duplicate migration versions', async () => {
    await writeMigration('001_first.sql', 'SELECT 1;');
    await writeMigration('001_second.sql', 'SELECT 2;');

    await assert.rejects(
        () => loadMigrations(migrationsDirectory),
        /Duplicate migration version: 1/,
    );
});

test('applies pending migrations inside transactions', async () => {
    await writeMigration('001_first.sql', 'SELECT 1;');
    await writeMigration('002_second.sql', 'SELECT 2;');

    const client = createClient();
    const applied = await runMigrations(
        client,
        migrationsDirectory,
    );

    assert.deepEqual(applied, [
        '001_first.sql',
        '002_second.sql',
    ]);

    const queries = client.calls.map((call) => call.sql);

    assert.equal(
        queries.filter((sql) => sql === 'BEGIN').length,
        2,
    );
    assert.equal(
        queries.filter((sql) => sql === 'COMMIT').length,
        2,
    );
    assert.equal(
        queries.filter((sql) =>
            sql.startsWith('INSERT INTO schema_migrations'),
        ).length,
        2,
    );
    assert.equal(queries.includes('ROLLBACK'), false);
});

test('does not run an already applied migration again', async () => {
    await writeMigration('001_first.sql', 'SELECT 1;');

    const [migration] = await loadMigrations(migrationsDirectory);

    const client = createClient({
        appliedRows: [{
            version: migration.version,
            name: migration.name,
            checksum: migration.checksum,
        }],
    });

    const applied = await runMigrations(
        client,
        migrationsDirectory,
    );

    assert.deepEqual(applied, []);
    assert.equal(
        client.calls.some((call) => call.sql === 'BEGIN'),
        false,
    );
});

test('rejects changes to an applied migration file', async () => {
    await writeMigration('001_first.sql', 'SELECT 1;');

    const client = createClient({
        appliedRows: [{
            version: 1,
            name: '001_first.sql',
            checksum: '0'.repeat(64),
        }],
    });

    await assert.rejects(
        () => runMigrations(client, migrationsDirectory),
        /no longer matches its file/,
    );
});

test('rolls back a failed migration', async () => {
    const failingSql = 'BROKEN SQL';

    await writeMigration('001_broken.sql', failingSql);

    const client = createClient({ failOnSql: failingSql });

    await assert.rejects(
        () => runMigrations(client, migrationsDirectory),
        /Migration 001_broken.sql failed/,
    );

    assert.equal(
        client.calls.at(-1).sql,
        'ROLLBACK',
    );
    assert.equal(
        client.calls.some((call) =>
            call.sql.startsWith('INSERT INTO schema_migrations'),
        ),
        false,
    );
});