function createThoughtController({
    thoughtService,
    reportRequestError,
}) {
    return {
        async list(request, response) {
            try {
                const thoughts =
                    await thoughtService.listThoughts(
                        request.auth.userId,
                    );

                return response.json(thoughts);
            } catch {
                reportRequestError(
                    request,
                    'thought_list_failed',
                );

                return response.status(500).json({
                    message: 'Failed to fetch thoughts',
                });
            }
        },

        async create(request, response) {
            try {
                const result =
                    await thoughtService.createThought(
                        request.auth.userId,
                        request.body,
                    );

                if (result.status === 'invalid') {
                    return response.status(400).json({
                        message: 'Invalid thought data',
                        errors: result.errors,
                    });
                }

                return response.status(201).json(
                    result.thought,
                );
            } catch {
                reportRequestError(
                    request,
                    'thought_creation_failed',
                );

                return response.status(500).json({
                    message: 'Failed to create thought',
                });
            }
        },

        async update(request, response) {
            try {
                const result =
                    await thoughtService.updateThought(
                        request.auth.userId,
                        request.params.id,
                        request.body,
                    );

                if (result.status === 'invalid_id') {
                    return response.status(400).json({
                        message: 'Invalid thought id',
                    });
                }

                if (result.status === 'invalid') {
                    return response.status(400).json({
                        message: 'Invalid thought data',
                        errors: result.errors,
                    });
                }

                if (result.status === 'not_found') {
                    return response.status(404).json({
                        message: 'Thought not found',
                    });
                }

                return response.json(result.thought);
            } catch {
                reportRequestError(
                    request,
                    'thought_update_failed',
                );

                return response.status(500).json({
                    message: 'Failed to update thought',
                });
            }
        },

        async remove(request, response) {
            try {
                const result =
                    await thoughtService.deleteThought(
                        request.auth.userId,
                        request.params.id,
                    );

                if (result.status === 'invalid_id') {
                    return response.status(400).json({
                        message: 'Invalid thought id',
                    });
                }

                if (result.status === 'not_found') {
                    return response.status(404).json({
                        message: 'Thought not found',
                    });
                }

                return response.status(204).send();
            } catch {
                reportRequestError(
                    request,
                    'thought_deletion_failed',
                );

                return response.status(500).json({
                    message: 'Failed to delete thought',
                });
            }
        },
    };
}

module.exports = {
    createThoughtController,
};
