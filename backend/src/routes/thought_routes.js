const express = require('express');

function createThoughtRoutes({
    thoughtController,
    requireAuthentication,
}) {
    const router = express.Router();

    router.get(
        '/thoughts',
        requireAuthentication,
        thoughtController.list,
    );
    router.post(
        '/thoughts',
        requireAuthentication,
        thoughtController.create,
    );
    router.patch(
        '/thoughts/:id',
        requireAuthentication,
        thoughtController.update,
    );
    router.delete(
        '/thoughts/:id',
        requireAuthentication,
        thoughtController.remove,
    );

    return router;
}

module.exports = {
    createThoughtRoutes,
};
