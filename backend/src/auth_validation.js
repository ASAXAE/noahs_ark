function validateRegistrationInput(body = {}) {
    const input =
        body !== null && typeof body === 'object'
            ? body
            : {};

    const displayName =
        typeof input.displayName === 'string'
            ? input.displayName.trim()
            : '';

    const email =
        typeof input.email === 'string'
            ? input.email.trim().toLowerCase()
            : '';

    const password =
        typeof input.password === 'string'
            ? input.password
            : '';

    const errors = [];

    if (displayName.length === 0) {
        errors.push('displayName is required');
    }

    if (displayName.length > 50) {
        errors.push('displayName must not exceed 50 characters');
    }

    if (email.length === 0) {
        errors.push('email is required');
    } else if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
        errors.push('email is invalid');
    }

    if (email.length > 255) {
        errors.push('email must not exceed 255 characters');
    }

    if (password.length === 0) {
        errors.push('password is required');
    } else if (password.length < 8) {
        errors.push('password must contain at least 8 characters');
    } else if (!/[A-Za-z]/.test(password) || !/\d/.test(password)) {
        errors.push(
            'password must contain at least one letter and one number',
        );
    }

    if (password.length > 72) {
        errors.push('password must not exceed 72 characters');
    }

    return {
        errors,
        value: {
            displayName,
            email,
            password,
        },
    };
}

function validateLoginInput(body = {}) {
    const input =
        body !== null && typeof body === 'object'
            ? body
            : {};

    const email =
        typeof input.email === 'string'
            ? input.email.trim().toLowerCase()
            : '';

    const password =
        typeof input.password === 'string'
            ? input.password
            : '';

    const errors = [];

    if (email.length === 0) {
        errors.push('email is required');
    } else if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
        errors.push('email is invalid');
    }

    if (email.length > 255) {
        errors.push('email must not exceed 255 characters');
    }

    if (password.length === 0) {
        errors.push('password is required');
    }

    if (password.length > 72) {
        errors.push('password must not exceed 72 characters');
    }

    return {
        errors,
        value: {
            email,
            password,
        },
    };
}

function validatePasswordResetRequestInput(body = {}) {
    const input =
        body !== null && typeof body === 'object'
            ? body
            : {};

    const email =
        typeof input.email === 'string'
            ? input.email.trim().toLowerCase()
            : '';

    const errors = [];

    if (email.length === 0) {
        errors.push('email is required');
    } else if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
        errors.push('email is invalid');
    }

    if (email.length > 255) {
        errors.push('email must not exceed 255 characters');
    }

    return {
        errors,
        value: {
            email,
        },
    };
}

function validatePasswordResetConfirmationInput(body = {}) {
    const input =
        body !== null && typeof body === 'object'
            ? body
            : {};

    const token =
        typeof input.token === 'string'
            ? input.token.trim().toLowerCase()
            : '';

    const password =
        typeof input.password === 'string'
            ? input.password
            : '';

    const errors = [];

    if (token.length === 0) {
        errors.push('token is required');
    } else if (!/^[0-9a-f]{64}$/.test(token)) {
        errors.push('token is invalid');
    }

    if (password.length === 0) {
        errors.push('password is required');
    } else if (password.length < 8) {
        errors.push('password must contain at least 8 characters');
    } else if (
        !/[A-Za-z]/.test(password) ||
        !/\d/.test(password)
    ) {
        errors.push(
            'password must contain at least one letter and one number',
        );
    }

    if (password.length > 72) {
        errors.push('password must not exceed 72 characters');
    }

    return {
        errors,
        value: {
            token,
            password,
        },
    };
}

module.exports = {
    validateRegistrationInput,
    validateLoginInput,
    validatePasswordResetRequestInput,
    validatePasswordResetConfirmationInput,
};