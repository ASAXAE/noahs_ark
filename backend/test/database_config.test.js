const {
    test,
} = require('node:test');

const assert = require('node:assert/strict');

const {
    createDatabaseConfig,
} = require('../src/database_config');

const baseEnvironment = {
    DB_HOST: 'localhost',
    DB_PORT: '5432',
    DB_NAME: 'noahs_ark',
    DB_USER: 'postgres',
    DB_PASSWORD: 'test-password',
};

test('disables database TLS by default', () => {
    assert.deepEqual(
        createDatabaseConfig(baseEnvironment),
        {
            host: 'localhost',
            port: 5432,
            database: 'noahs_ark',
            user: 'postgres',
            password: 'test-password',
            ssl: false,
        },
    );
});

test('requires encrypted database transport', () => {
    const config = createDatabaseConfig({
        ...baseEnvironment,
        DB_SSL_MODE: 'require',
    });

    assert.deepEqual(config.ssl, {
        rejectUnauthorized: false,
    });
});

test('rejects an unsupported database TLS mode', () => {
    assert.throws(
        () => createDatabaseConfig({
            ...baseEnvironment,
            DB_SSL_MODE: 'unexpected',
        }),
        /DB_SSL_MODE must be "disable" or "require"/,
    );
});
