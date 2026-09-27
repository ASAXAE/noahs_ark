function createHealthRepository(database) {
    return {
        async checkConnection(queryTimeoutMs = 3000) {
            await database.query({
                text: 'SELECT 1',
                query_timeout: queryTimeoutMs,
            });
        },
    };
}

module.exports = {
    createHealthRepository,
};
