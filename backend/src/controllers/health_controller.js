function createHealthController({
    healthService,
}) {
    return {
        liveness(request, response) {
            response.set('Cache-Control', 'no-store');

            return response.json({
                status: 'ok',
                message: "Noah's Ark API is running",
            });
        },

        async readiness(request, response) {
            const isReady =
                await healthService.isReady();

            response.set('Cache-Control', 'no-store');

            if (!isReady) {
                return response.status(503).json({
                    status: 'unavailable',
                });
            }

            return response.json({
                status: 'ready',
            });
        },
    };
}

module.exports = {
    createHealthController,
};
