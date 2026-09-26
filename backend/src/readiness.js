const defaultQueryTimeoutMs = 3000;

async function checkDatabaseReadiness(
    database,
    queryTimeoutMs = defaultQueryTimeoutMs,
) {
    try {
        await database.query({
            text: 'SELECT 1',
            query_timeout: queryTimeoutMs,
        });

        return true;
    } catch {
        return false;
    }
}

module.exports = {
    checkDatabaseReadiness,
};
