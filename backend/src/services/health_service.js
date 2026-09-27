function createHealthService({
    healthRepository,
}) {
    return {
        async isReady() {
            try {
                await healthRepository.checkConnection();
                return true;
            } catch {
                return false;
            }
        },
    };
}

module.exports = {
    createHealthService,
};
