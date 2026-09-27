function createDatabaseConfig(
    environment = process.env,
) {
    const sslMode =
        environment.DB_SSL_MODE ?? 'disable';

    if (
        sslMode !== 'disable' &&
        sslMode !== 'require'
    ) {
        throw new Error(
            'DB_SSL_MODE must be "disable" or "require"',
        );
    }

    const connectionTimeoutMillis = Number(
        environment.DB_CONNECTION_TIMEOUT_MS ?? '3000',
    );

    if (
        !Number.isInteger(connectionTimeoutMillis) ||
        connectionTimeoutMillis <= 0
    ) {
        throw new Error(
            'DB_CONNECTION_TIMEOUT_MS must be a positive integer',
        );
    }

    return {
        host: environment.DB_HOST,
        port: Number(environment.DB_PORT),
        database: environment.DB_NAME,
        user: environment.DB_USER,
        password: environment.DB_PASSWORD,
        connectionTimeoutMillis,
        ssl:
            sslMode === 'require'
                ? {
                    rejectUnauthorized: false,
                }
                : false,
    };
}

module.exports = {
    createDatabaseConfig,
};
