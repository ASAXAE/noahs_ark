function validateThoughtInput(body = {}) {
    const title =
        typeof body.title === 'string'
            ? body.title.trim()
            : '';

    const content =
        typeof body.content === 'string'
            ? body.content
            : '';

    const tag =
        typeof body.tag === 'string'
            ? body.tag.trim()
            : '';

    const errors = [];

    if (title.length > 50) {
        errors.push('title must not exceed 50 characters');
    }

    if (content.trim().length === 0) {
        errors.push('content is required');
    }

    if (tag.length === 0) {
        errors.push('tag is required');
    }

    if (tag.length > 20) {
        errors.push('tag must not exceed 20 characters');
    }

    return {
        errors,
        value: {
            title,
            content,
            tag,
        },
    };
}

module.exports = {
    validateThoughtInput,
};
