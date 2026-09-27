const {
    validateThoughtInput,
} = require('../validators/thought_validation');

function isValidThoughtId(thoughtId) {
    return /^[1-9]\d*$/.test(thoughtId);
}

function validateThoughtUpdate(input) {
    const {
        title,
        content,
        tag,
        isFavorite = false,
    } = input;
    const errors = [];

    if (typeof title !== 'string') {
        errors.push('title must be a string');
    }

    if (
        typeof content !== 'string' ||
        content.trim().length === 0
    ) {
        errors.push('content is required');
    }

    if (
        typeof tag !== 'string' ||
        tag.trim().length === 0
    ) {
        errors.push('tag is required');
    }

    if (typeof isFavorite !== 'boolean') {
        errors.push('isFavorite must be a boolean');
    }

    if (errors.length > 0) {
        return {
            errors,
        };
    }

    return {
        errors,
        value: {
            title: title.trim(),
            content: content.trim(),
            tag: tag.trim(),
            isFavorite,
        },
    };
}

function createThoughtService({
    thoughtRepository,
}) {
    return {
        async listThoughts(userId) {
            return thoughtRepository.listForUser(userId);
        },

        async createThought(userId, input) {
            const validation =
                validateThoughtInput(input);

            if (validation.errors.length > 0) {
                return {
                    status: 'invalid',
                    errors: validation.errors,
                };
            }

            const thought =
                await thoughtRepository.createForUser(
                    userId,
                    validation.value,
                );

            return {
                status: 'created',
                thought,
            };
        },

        async updateThought(userId, thoughtId, input) {
            if (!isValidThoughtId(thoughtId)) {
                return {
                    status: 'invalid_id',
                };
            }

            const validation =
                validateThoughtUpdate(input);

            if (validation.errors.length > 0) {
                return {
                    status: 'invalid',
                    errors: validation.errors,
                };
            }

            const thought =
                await thoughtRepository.updateForUser(
                    userId,
                    thoughtId,
                    validation.value,
                );

            if (thought === undefined) {
                return {
                    status: 'not_found',
                };
            }

            return {
                status: 'updated',
                thought,
            };
        },

        async deleteThought(userId, thoughtId) {
            if (!isValidThoughtId(thoughtId)) {
                return {
                    status: 'invalid_id',
                };
            }

            const deleted =
                await thoughtRepository.deleteForUser(
                    userId,
                    thoughtId,
                );

            return {
                status: deleted
                    ? 'deleted'
                    : 'not_found',
            };
        },
    };
}

module.exports = {
    createThoughtService,
};
