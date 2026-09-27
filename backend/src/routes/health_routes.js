const express = require('express');

function createHealthRoutes({
    healthController,
}) {
    const router = express.Router();

    router.get(
        '/health',
        healthController.liveness,
    );
    router.get(
        '/readyz',
        healthController.readiness,
    );

    return router;
}

module.exports = {
    createHealthRoutes,
};
