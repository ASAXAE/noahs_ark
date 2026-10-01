const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const { test } = require('node:test');
const { assertLocalTarget, main, matchingMigrationSql } = require('../scripts/postgres_backup');

const target = 'noahs_ark_restore_drill_20260929000000_0123abcd';
const config = { host: '127.0.0.1', database: 'noahs_ark' };

test('restore guard accepts only an explicitly named loopback drill target', () => {
    for (const host of ['127.0.0.1', 'localhost', '::1']) {
        assert.doesNotThrow(() => assertLocalTarget({ ...config, host }, target));
    }
});

test('restore guard rejects remote hosts and existing application databases', () => {
    assert.throws(() => assertLocalTarget({ ...config, host: 'postgres.railway.internal' }, target));
    assert.throws(() => assertLocalTarget(config, 'noahs_ark'));
    assert.throws(() => assertLocalTarget({ ...config, database: target }, target));
});

test('restore guard rejects SQL fragments and malformed drill identifiers', () => {
    for (const database of ['postgres', 'noahs_ark_restore_drill', `${target}; DROP DATABASE postgres`,
        'noahs_ark_restore_drill_20260929000000_zzzzzzzz']) {
        assert.throws(() => assertLocalTarget(config, database));
    }
});

test('migration checksum matching allows only LF/CRLF conversion', () => {
    const lf = 'CREATE TABLE example (id INT);\n';
    const crlf = lf.replace(/\n/g, '\r\n');
    const checksum = crypto.createHash('sha256').update(lf).digest('hex');
    assert.equal(matchingMigrationSql(crlf, checksum), lf);
    assert.equal(matchingMigrationSql(lf, checksum), lf);
    assert.equal(matchingMigrationSql('CREATE TABLE example (id BIGINT);\r\n', checksum), null);
});

test('a corrupted archive is rejected before any database connection or creation', async () => {
    const directory = await fs.mkdtemp(path.join(os.tmpdir(), 'noahs-ark-backup-test-'));
    const archive = path.join(directory, 'corrupt.dump');
    try {
        await fs.writeFile(archive, 'Corrupted archive');
        await fs.writeFile(`${archive}.json`, JSON.stringify({
            formatVersion: 1, archive: { filename: 'corrupt.dump', sha256: '0'.repeat(64) },
        }));
        await assert.rejects(() => main(['restore-drill', archive]), /Archive SHA-256 mismatch/);
    } finally {
        await fs.unlink(archive);
        await fs.unlink(`${archive}.json`);
        await fs.rmdir(directory);
    }
});
