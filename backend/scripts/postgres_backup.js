const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const fs = require('node:fs/promises');
const net = require('node:net');
const path = require('node:path');
const { isDeepStrictEqual } = require('node:util');
const { execFile, spawn } = require('node:child_process');
const { Client } = require('pg');
const dotenv = require('dotenv');
const { createDatabaseConfig } = require('../src/config/database_config');
const { loadMigrations, runMigrations } = require('../src/migrations/migration_runner');

const root = path.resolve(__dirname, '../..');
const backupDirectory = path.join(root, '.backups', 'postgres');
const migrationsDirectory = path.join(root, 'backend', 'sql');
const railwayProject = '0943410e-78e5-4ff0-8e66-823cc5b26a50';
const railwayEnvironment = 'staging';
const railwayService = 'Postgres';
const tables = [
    'email_verification_tokens',
    'password_reset_tokens',
    'refresh_tokens',
    'schema_migrations',
    'thoughts',
    'users',
];

function emit(event, details = {}) {
    console.log(JSON.stringify({ event, ...details }));
}

function safeError(message) {
    const error = new Error(message);
    error.safe = true;
    return error;
}

function railwayBinary() {
    return process.env.RAILWAY_BIN || (process.platform === 'win32'
        ? path.join(process.env.APPDATA, 'npm/node_modules/@railway/cli/bin/railway.exe')
        : 'railway');
}

function postgresBinary(name) {
    const directory = process.env.PG_BIN || (process.platform === 'win32'
        ? 'C:\\Program Files\\PostgreSQL\\18\\bin'
        : null);
    return directory ? path.join(directory, `${name}${process.platform === 'win32' ? '.exe' : ''}`) : name;
}

async function run(binary, args, options = {}) {
    try {
        const { input = '', ...executionOptions } = options;
        return await new Promise((resolve, reject) => {
            const child = execFile(binary, args, {
                windowsHide: true,
                timeout: 120000,
                maxBuffer: 32 * 1024 * 1024,
                ...executionOptions,
            }, (error, stdout, stderr) => {
                if (error) {
                    error.stdout = stdout;
                    error.stderr = stderr;
                    reject(error);
                } else {
                    resolve({ stdout, stderr });
                }
            });
            child.stdin.on('error', () => {});
            child.stdin.end(input);
        });
    } catch (error) {
        // CLI output may contain credentials, and PostgreSQL errors may contain rows.
        const code = /^[A-Z0-9_]+$/.test(String(error.code)) ? String(error.code) : 'FAILED';
        const output = `${error.stdout || ''}\n${error.stderr || ''}`;
        const detail = /non.?interactive|terminal|prompt/i.test(output) ? 'interactive confirmation required' :
            /unauthorized|not authenticated|login/i.test(output) ? 'authentication rejected' :
            /timeout|timed out/i.test(output) ? 'connection timed out' :
            /resolve|dns|sending request|connect error/i.test(output) ? 'network request failed' : 'command rejected';
        throw safeError(`${path.basename(binary)} ${args[0] || ''} failed (${code}, ${detail}); raw output withheld`);
    }
}

async function railwayApi(document, variables) {
    const { stdout } = await run(railwayBinary(), ['api', document, '--variables', '@-', '--compact'], {
        input: JSON.stringify(variables),
    });
    const response = JSON.parse(stdout);
    if (response.errors?.length) throw safeError('Railway API rejected the temporary SSH key operation');
    return response.data || response;
}

async function prepareBackupDirectory() {
    await fs.mkdir(backupDirectory, { recursive: true, mode: 0o700 });
    if (process.platform === 'win32') {
        const { stdout } = await run('whoami.exe', []);
        await run('icacls.exe', [backupDirectory, '/inheritance:r', '/grant:r',
            `${stdout.trim()}:(OI)(CI)F`, '*S-1-5-18:(OI)(CI)F', '*S-1-5-32-544:(OI)(CI)F']);
    }
}

async function localConfig() {
    const environment = {
        ...dotenv.parse(await fs.readFile(path.join(root, 'backend', '.env'))),
        ...process.env,
    };
    return createDatabaseConfig(environment);
}

function assertLocalTarget(config, database) {
    if (!['localhost', '127.0.0.1', '::1'].includes(config.host) ||
        !/^noahs_ark_restore_drill_[0-9]{14}_[0-9a-f]{8}$/.test(database) ||
        database === config.database) {
        throw safeError('Restore targets must be new, explicitly named loopback drill databases');
    }
}

function postgresEnvironment(config) {
    // Never place a password in argv, a connection URL, a file or console output.
    return {
        ...process.env,
        PGHOST: config.host,
        PGPORT: String(config.port),
        PGDATABASE: config.database,
        PGUSER: config.user,
        PGPASSWORD: config.password,
        PGSSLMODE: config.ssl ? 'require' : 'disable',
        PGCONNECT_TIMEOUT: '10',
        PGOPTIONS: '-c timezone=UTC',
    };
}

async function freePort() {
    const server = net.createServer();
    await new Promise((resolve, reject) => {
        server.once('error', reject);
        server.listen(0, '127.0.0.1', resolve);
    });
    const port = server.address().port;
    await new Promise((resolve) => server.close(resolve));
    return port;
}

async function acceptsConnection(port) {
    return new Promise((resolve) => {
        const socket = net.connect({ host: '127.0.0.1', port });
        const finish = (connected) => {
            socket.destroy();
            resolve(connected);
        };
        socket.setTimeout(500);
        socket.once('connect', () => finish(true));
        socket.once('error', () => finish(false));
        socket.once('timeout', () => finish(false));
    });
}

async function stopTunnel(child) {
    if (!child || !child.pid || child.exitCode !== null || child.signalCode !== null) return;
    if (process.platform === 'win32') {
        // Stop only this script's tunnel process and its SSH children.
        await run('taskkill.exe', ['/PID', String(child.pid), '/T', '/F']);
    } else {
        child.kill('SIGTERM');
        await new Promise((resolve) => child.once('close', resolve));
    }
    emit('tunnel_closed');
}

async function sourceConnection(kind) {
    if (kind === 'local') return { config: await localConfig(), close: async () => {} };
    if (kind !== 'railway') throw safeError('Source must be local or railway');
    const binary = railwayBinary();
    const { stdout } = await run(binary, [
        'variables', '--project', railwayProject,
        '--environment', railwayEnvironment, '--service', railwayService, '--json',
    ]);
    const variables = JSON.parse(stdout);
    for (const key of ['PGDATABASE', 'PGUSER', 'PGPASSWORD']) {
        if (!variables[key]) throw safeError(`Railway ${key} is unavailable`);
    }
    emit('source_variables_loaded');
    await prepareBackupDirectory();
    const keyDirectory = await fs.mkdtemp(path.join(backupDirectory, 'ssh-'));
    const identity = path.join(keyDirectory, 'identity');
    let fingerprint;
    let keyId;
    let registered = false;
    let tunnel;
    const close = async () => {
        try {
            await stopTunnel(tunnel);
        } finally {
            try {
                if (registered) {
                    const result = await railwayApi(
                        'mutation Revoke($id: String!) { sshPublicKeyDelete(id: $id) }', { id: keyId });
                    assert.equal(result.sshPublicKeyDelete, true, 'Temporary SSH key revocation failed');
                    registered = false;
                    emit('temporary_ssh_key_revoked');
                }
            } finally {
                // Remove only the generated files under this invocation's private directory.
                assert.equal(path.dirname(keyDirectory), backupDirectory);
                assert.match(path.basename(keyDirectory), /^ssh-[A-Za-z0-9]+$/);
                for (const name of ['identity', 'identity.pub', 'known_hosts', 'known_hosts.old']) {
                    await fs.unlink(path.join(keyDirectory, name)).catch((error) => {
                        if (error.code !== 'ENOENT') throw error;
                    });
                }
                await fs.rmdir(keyDirectory);
            }
        }
    };
    try {
        await run('ssh-keygen', ['-t', 'ed25519', '-N', '', '-f', identity,
            '-C', `noahs-ark-backup-${crypto.randomUUID()}`]);
        const { stdout: keyInfo } = await run('ssh-keygen', ['-l', '-f', `${identity}.pub`]);
        fingerprint = keyInfo.split(/\s+/)[1];
        assert.match(fingerprint, /^SHA256:[A-Za-z0-9+/]+$/);
        // CLI 5.62.1 only discovers keys in ~/.ssh even when --key is an absolute path.
        // Register the temporary public key through Railway's documented GraphQL API.
        const result = await railwayApi(`
            mutation Register($input: SshPublicKeyCreateInput!) {
                sshPublicKeyCreate(input: $input) { id fingerprint }
            }
        `, { input: {
            name: `day73-backup-${path.basename(keyDirectory)}`,
            publicKey: (await fs.readFile(`${identity}.pub`, 'utf8')).trim(),
        } });
        keyId = result.sshPublicKeyCreate.id;
        registered = true;
        assert.equal(result.sshPublicKeyCreate.fingerprint, fingerprint);
        emit('temporary_ssh_key_registered');
        const { stdout: sshConfig } = await run(binary, [
            'ssh', 'config', '--project', railwayProject,
            '--environment', railwayEnvironment, '--service', railwayService, '--dry-run',
        ]);
        const target = sshConfig.match(/^\s+User ([a-z0-9-]+)\s*$/m)?.[1];
        assert.ok(target && /^\s+HostName ssh\.railway\.com\s*$/m.test(sshConfig));
        const remotePort = Number(variables.PGPORT || 5432);
        assert.ok(Number.isInteger(remotePort) && remotePort > 0 && remotePort < 65536);
        const port = await freePort();
        tunnel = spawn('ssh', [
            '-N', '-T', '-i', identity, '-F', process.platform === 'win32' ? 'NUL' : '/dev/null',
            '-o', 'IdentitiesOnly=yes', '-o', 'BatchMode=yes',
            '-o', 'StrictHostKeyChecking=accept-new', '-o', `UserKnownHostsFile=${path.join(keyDirectory, 'known_hosts')}`,
            '-o', 'ExitOnForwardFailure=yes', '-o', 'ConnectTimeout=45', '-o', 'ServerAliveInterval=15',
            '-L', `127.0.0.1:${port}:127.0.0.1:${remotePort}`, `${target}@ssh.railway.com`,
        ], { windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'] });
        let failed = false;
        let sshFailure = '';
        tunnel.once('error', () => { failed = true; });
        tunnel.stdout.resume();
        tunnel.stderr.on('data', (chunk) => { sshFailure += chunk.toString(); });
        emit('tunnel_starting', { project: 'noahs-ark-staging', environment: railwayEnvironment });
        const deadline = Date.now() + 60000;
        while (Date.now() < deadline) {
            if (failed || tunnel.exitCode !== null) break;
            if (await acceptsConnection(port)) {
                return {
                    config: {
                        host: '127.0.0.1', port,
                        database: variables.PGDATABASE,
                        user: variables.PGUSER, password: variables.PGPASSWORD,
                        ssl: { rejectUnauthorized: false }, connectionTimeoutMillis: 10000,
                    }, close,
                };
            }
            await new Promise((resolve) => setTimeout(resolve, 250));
        }
        const reason = /Permission denied/i.test(sshFailure) ? 'SSH key rejected' :
            /timed out/i.test(sshFailure) ? 'SSH connection timed out' :
            /resolve hostname/i.test(sshFailure) ? 'SSH DNS lookup failed' : 'SSH tunnel did not become ready';
        throw safeError(reason);
    } catch (error) {
        await close();
        throw error;
    }
}

async function connect(config) {
    const client = new Client({ ...config, query_timeout: 30000 });
    try {
        await client.connect();
        await client.query("SET TIME ZONE 'UTC'");
        return client;
    } catch (error) {
        await client.end();
        throw error;
    }
}

function matchingMigrationSql(sql, checksum) {
    const lf = sql.replace(/\r\n/g, '\n');
    return [sql, lf, lf.replace(/\n/g, '\r\n')].find((candidate) =>
        crypto.createHash('sha256').update(candidate).digest('hex') === checksum) ?? null;
}

async function runMigrationsWithSourceLineEndings(client, applied) {
    const files = await loadMigrations(migrationsDirectory);
    if (files.length !== applied.length || files.some((file, index) =>
        file.version !== applied[index].version || file.name !== applied[index].name)) {
        throw safeError('Restored migration versions or names differ from repository files');
    }
    await prepareBackupDirectory();
    const directory = await fs.mkdtemp(path.join(backupDirectory, 'migrations-'));
    const written = [];
    try {
        for (const [index, file] of files.entries()) {
            const sql = matchingMigrationSql(file.sql, applied[index].checksum);
            if (sql === null) throw safeError(`Migration ${file.version} differs beyond line endings`);
            await fs.writeFile(path.join(directory, file.name), sql, { flag: 'wx', mode: 0o600 });
            written.push(file.name);
        }
        return await runMigrations(client, directory);
    } finally {
        for (const name of written) await fs.unlink(path.join(directory, name));
        await fs.rmdir(directory);
    }
}

async function inventory(client) {
    const actualTables = (await client.query(`
        SELECT tablename FROM pg_tables WHERE schemaname = 'public' ORDER BY tablename
    `)).rows.map(({ tablename }) => tablename);
    if (!isDeepStrictEqual(actualTables, tables)) {
        emit('schema_inventory_mismatch', {
            missingTables: tables.filter((name) => !actualTables.includes(name)),
            extraTables: actualTables.filter((name) => !tables.includes(name)),
        });
        throw safeError('Database table set differs from the expected application schema');
    }
    const data = {};
    for (const table of tables) {
        const result = await client.query(`
            SELECT to_jsonb(t)::text AS row FROM public.${table} AS t
            ORDER BY ${table === 'schema_migrations' ? 'version' : 'id'}
        `);
        const digest = crypto.createHash('sha256');
        for (const { row } of result.rows) digest.update(row + '\n');
        data[table] = { count: result.rowCount, sha256: digest.digest('hex') };
    }
    const columns = (await client.query(`
        SELECT table_name, column_name, ordinal_position, data_type,
               is_nullable, column_default, character_maximum_length
        FROM information_schema.columns WHERE table_schema = 'public'
        ORDER BY table_name, ordinal_position
    `)).rows;
    const constraints = (await client.query(`
        SELECT c.relname AS table_name, con.conname AS name, con.contype AS type,
               pg_get_constraintdef(con.oid) AS definition
        FROM pg_constraint con JOIN pg_class c ON c.oid = con.conrelid
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'public' ORDER BY c.relname, con.conname
    `)).rows;
    const indexes = (await client.query(`
        SELECT tablename, indexname, indexdef FROM pg_indexes
        WHERE schemaname = 'public' ORDER BY tablename, indexname
    `)).rows;
    const sequences = {};
    for (const table of tables.filter((name) => name !== 'schema_migrations')) {
        sequences[table] = (await client.query(`
            SELECT last_value::text, is_called FROM public.${table}_id_seq
        `)).rows[0];
    }
    const migrations = (await client.query(`
        SELECT version, name, checksum FROM schema_migrations ORDER BY version
    `)).rows;
    const migrationFiles = await loadMigrations(migrationsDirectory);
    const differences = migrationFiles.map(({ version, name, checksum, sql }) => {
        const actual = migrations.find((entry) => entry.version === version);
        return {
            version, expectedName: name, actualName: actual?.name || null,
            checksumMatches: actual?.checksum === checksum,
            lineEndingOnlyDifference: actual && matchingMigrationSql(sql, actual.checksum) !== null,
        };
    }).filter(({ expectedName, actualName, lineEndingOnlyDifference }) =>
        expectedName !== actualName || !lineEndingOnlyDifference);
    const unexpectedVersions = migrations.filter(({ version }) =>
        !migrationFiles.some((file) => file.version === version)).map(({ version }) => version);
    if (differences.length || unexpectedVersions.length) {
        emit('migration_history_mismatch', {
            differences, unexpectedVersions,
        });
        throw safeError('Migration history differs beyond line endings from repository SQL');
    }
    return { data, columns, constraints, indexes, sequences, migrations };
}

async function sha256File(filename) {
    return crypto.createHash('sha256').update(await fs.readFile(filename)).digest('hex');
}

async function writeJson(filename, value) {
    await fs.writeFile(filename, JSON.stringify(value, null, 2) + '\n', { flag: 'wx', mode: 0o600 });
}

async function backup(client, config, kind, label = kind) {
    await prepareBackupDirectory();
    const stamp = new Date().toISOString().replace(/[-:]/g, '').replace(/\.\d{3}Z$/, 'Z');
    const archive = path.join(backupDirectory, `${label}-${stamp}-${crypto.randomBytes(4).toString('hex')}.dump`);
    const started = Date.now();
    await client.query('BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY');
    let manifest;
    try {
        const snapshot = (await client.query('SELECT pg_export_snapshot() AS id')).rows[0].id;
        const contents = await inventory(client);
        const serverVersion = (await client.query('SHOW server_version')).rows[0].server_version;
        const { stdout: pgDumpVersion } = await run(postgresBinary('pg_dump'), ['--version']);
        await run(postgresBinary('pg_dump'), [
            '--format=custom', '--no-owner', '--no-acl', '--no-password',
            '--snapshot', snapshot, '--lock-wait-timeout=10000', '--file', archive,
        ], { env: postgresEnvironment(config) });
        await run(postgresBinary('pg_restore'), ['--list', archive]);
        manifest = {
            formatVersion: 1, createdAt: new Date().toISOString(),
            source: { kind, database: config.database, serverVersion },
            archive: {
                filename: path.basename(archive), bytes: (await fs.stat(archive)).size,
                sha256: await sha256File(archive), pgDumpVersion: pgDumpVersion.trim(),
            },
            inventory: contents,
            backupDurationMs: Date.now() - started,
        };
        await writeJson(`${archive}.json`, manifest);
    } finally {
        await client.query('ROLLBACK');
    }
    emit('backup_created', {
        archive, bytes: manifest.archive.bytes,
        rows: Object.fromEntries(Object.entries(manifest.inventory.data).map(([name, value]) => [name, value.count])),
    });
    return { archive, manifest };
}

async function assertRejected(client, sql, values, code) {
    await client.query('SAVEPOINT constraint_probe');
    let rejected = false;
    try {
        await client.query(sql, values);
    } catch (error) {
        assert.equal(error.code, code);
        rejected = true;
    } finally {
        await client.query('ROLLBACK TO SAVEPOINT constraint_probe');
    }
    assert.ok(rejected, `Expected PostgreSQL rejection ${code}`);
}

async function verifyBehavior(client, fixture) {
    await client.query('BEGIN');
    try {
        const email = `restore-${crypto.randomUUID()}@example.invalid`;
        const { rows: [user] } = await client.query(`
            INSERT INTO users (display_name, email, password_hash) VALUES ($1, $2, $3) RETURNING id
        `, ['Restore probe', email, 'inert-restore-test-hash']);
        const { rows: [thought] } = await client.query(`
            INSERT INTO thoughts (user_id, title, content, tag) VALUES ($1, $2, $3, $4) RETURNING id
        `, [user.id, 'Restore probe', 'Disposable restore validation', 'day73']);
        const tokenTables = ['email_verification_tokens', 'password_reset_tokens', 'refresh_tokens'];
        for (const table of tokenTables) {
            const hash = crypto.randomBytes(32).toString('hex');
            const extraColumn = table === 'refresh_tokens' ? ', family_id' : '';
            const extraValue = table === 'refresh_tokens' ? ', $3' : '';
            const params = [user.id, hash];
            if (table === 'refresh_tokens') params.push(crypto.randomUUID());
            await client.query(`INSERT INTO ${table} (user_id, token_hash, expires_at${extraColumn})
                VALUES ($1, $2, NOW() + INTERVAL '1 hour'${extraValue})`, params);
        }
        await assertRejected(client,
            'INSERT INTO users (display_name, email) VALUES ($1, $2)', ['Duplicate', email], '23505');
        await assertRejected(client,
            'INSERT INTO thoughts (user_id, content, tag) VALUES ($1, $2, $3)',
            ['-1', 'Foreign key probe', 'day73'], '23503');
        await assertRejected(client,
            'INSERT INTO password_reset_tokens (user_id, token_hash, expires_at) VALUES ($1, $2, NOW())',
            [user.id, 'invalid-hash'], '23514');
        await client.query('DELETE FROM users WHERE id = $1', [user.id]);
        for (const table of ['thoughts', ...tokenTables]) {
            assert.equal((await client.query(`SELECT COUNT(*)::int AS count FROM ${table} WHERE user_id = $1`,
                [user.id])).rows[0].count, 0, `Cascade failed for ${table}`);
        }
        if (fixture) {
            const { rows } = await client.query('SELECT title, content, tag FROM thoughts WHERE id = $1', [fixture.thoughtId]);
            assert.deepEqual(rows, [{ title: fixture.title, content: fixture.content, tag: 'day73' }]);
            assert.ok(BigInt(user.id) > BigInt(fixture.userId));
            assert.ok(BigInt(thought.id) > BigInt(fixture.thoughtId));
        }
    } finally {
        await client.query('ROLLBACK');
    }
}

async function restoreDrill(archive, fixture = null) {
    archive = path.resolve(archive);
    const manifest = JSON.parse(await fs.readFile(`${archive}.json`, 'utf8'));
    assert.equal(manifest.formatVersion, 1);
    assert.equal(manifest.archive.filename, path.basename(archive));
    assert.equal(await sha256File(archive), manifest.archive.sha256, 'Archive SHA-256 mismatch');
    await run(postgresBinary('pg_restore'), ['--list', archive]);
    const local = await localConfig();
    const stamp = new Date().toISOString().replace(/\D/g, '').slice(0, 14);
    const database = `noahs_ark_restore_drill_${stamp}_${crypto.randomBytes(4).toString('hex')}`;
    assertLocalTarget(local, database);
    const admin = await connect({ ...local, database: 'postgres' });
    let created = false;
    let restored;
    const started = Date.now();
    const report = { archive: path.basename(archive), database, startedAt: new Date().toISOString() };
    try {
        await admin.query(`CREATE DATABASE "${database}" TEMPLATE template0`);
        created = true;
        const target = { ...local, database };
        await run(postgresBinary('pg_restore'), [
            '--dbname', database, '--no-owner', '--no-acl', '--exit-on-error',
            '--single-transaction', '--no-password', archive,
        ], { env: postgresEnvironment(target) });
        restored = await connect(target);
        assert.deepEqual(await inventory(restored), manifest.inventory, 'Restored inventory differs from backup');
        const migrations = await runMigrationsWithSourceLineEndings(restored, manifest.inventory.migrations);
        assert.deepEqual(migrations, [], 'Restore unexpectedly required new migrations');
        await verifyBehavior(restored, fixture);
        await restored.query('ANALYZE');
        report.verified = true;
        report.checks = [
            'archive_sha256', 'all_table_row_counts_and_sha256', 'columns', 'constraints',
            'indexes', 'sequence_values', 'migration_checksums_and_idempotence',
            'sequence_insert', 'unique_email_rejection', 'foreign_key_rejection',
            'token_check_rejection', 'account_delete_cascades',
            ...(fixture ? ['synthetic_fixture_recovered'] : []),
        ];
        report.restoreAndVerifyDurationMs = Date.now() - started;
    } finally {
        await restored?.end();
        try {
            if (created) {
                assertLocalTarget(local, database);
                // Only drop the database created by this invocation; never force disconnect users.
                await admin.query(`DROP DATABASE "${database}"`);
                report.targetRemoved = true;
            }
        } finally {
            await admin.end();
        }
    }
    await writeJson(`${archive}.restore-${crypto.randomBytes(4).toString('hex')}.json`, report);
    emit('restore_verified', report);
    return report;
}

async function railwayDrill() {
    const source = await sourceConnection('railway');
    let client;
    let fixture;
    let baseline;
    try {
        client = await connect(source.config);
        baseline = await backup(client, source.config, 'railway', 'railway-baseline');
        const email = `day73-${crypto.randomUUID()}@example.invalid`;
        const title = 'Day 73 restore marker';
        const content = `Disposable backup exercise ${crypto.randomUUID()}`;
        await client.query('BEGIN');
        try {
            const { rows: [user] } = await client.query(`
                INSERT INTO users (display_name, email, password_hash) VALUES ($1, $2, $3) RETURNING id
            `, ['Day73 restore drill', email, 'inert-day73-test-hash']);
            const { rows: [thought] } = await client.query(`
                INSERT INTO thoughts (user_id, title, content, tag) VALUES ($1, $2, $3, $4) RETURNING id
            `, [user.id, title, content, 'day73']);
            await client.query('COMMIT');
            fixture = { userId: user.id, thoughtId: thought.id, email, title, content };
        } catch (error) {
            await client.query('ROLLBACK');
            throw error;
        }
        const drill = await backup(client, source.config, 'railway', 'railway-drill');
        await restoreDrill(drill.archive, fixture);
    } finally {
        try {
            if (client && fixture) {
                const cleanup = await client.query('DELETE FROM users WHERE id = $1 AND email = $2',
                    [fixture.userId, fixture.email]);
                assert.equal(cleanup.rowCount, 1, 'Staging fixture cleanup failed');
                const after = await inventory(client);
                assert.deepEqual(after.data, baseline.manifest.inventory.data, 'Original staging rows changed');
                emit('staging_fixture_removed', { originalRowsPreserved: true });
            }
        } finally {
            await client?.end();
            await source.close();
        }
    }
    // Verify the clean baseline as the retained recovery copy as well.
    await restoreDrill(baseline.archive);
    return baseline.archive;
}

async function main(args = process.argv.slice(2)) {
    const [command, value] = args;
    if (command === 'backup') {
        const source = await sourceConnection(value || 'local');
        let client;
        try {
            client = await connect(source.config);
            await backup(client, source.config, value || 'local');
        } finally {
            await client?.end();
            await source.close();
        }
    } else if (command === 'restore-drill' && value) {
        await restoreDrill(value);
    } else if (command === 'railway-drill') {
        await railwayDrill();
    } else {
        throw safeError('Usage: postgres_backup.js backup [local|railway] | restore-drill <archive> | railway-drill');
    }
}

if (require.main === module) {
    main().catch((error) => {
        emit('database_backup_failed', {
            reason: error.safe ? error.message : 'Database operation or verification failed; raw output withheld',
            code: /^[A-Z0-9_]+$/.test(String(error.code)) ? String(error.code) : undefined,
        });
        process.exitCode = 1;
    });
}

module.exports = { assertLocalTarget, main, matchingMigrationSql };
