const { describe, test } = require('node:test');
const assert = require('node:assert/strict');

const {
    validateRegistrationInput,
    validateLoginInput,
    validatePasswordResetRequestInput,
    validatePasswordResetConfirmationInput,
    validateAccountDeletionInput,
} = require('../src/auth_validation');

describe('validateRegistrationInput', () => {
    test('accepts valid registration data and normalizes it', () => {
        const result = validateRegistrationInput({
            displayName: '  Test User  ',
            email: '  TEST@EXAMPLE.COM  ',
            password: 'StrongPassword123',
        });

        assert.deepEqual(result.errors, []);

        assert.deepEqual(result.value, {
            displayName: 'Test User',
            email: 'test@example.com',
            password: 'StrongPassword123',
        });
    });

    test('accepts an eight-character password with letters and numbers', () => {
        const result = validateRegistrationInput({
            displayName: 'Test User',
            email: 'test@example.com',
            password: 'Ark2026a',
        });

        assert.deepEqual(result.errors, []);
    });

    test('rejects an invalid email', () => {
        const result = validateRegistrationInput({
            displayName: 'Test User',
            email: 'invalid-email',
            password: 'StrongPassword123',
        });

        assert.deepEqual(result.errors, [
            'email is invalid',
        ]);
    });

    test('rejects a password shorter than 8 characters', () => {
        const result = validateRegistrationInput({
            displayName: 'Test User',
            email: 'test@example.com',
            password: 'Pass123',
        });

        assert.deepEqual(result.errors, [
            'password must contain at least 8 characters',
        ]);
    });

    test('rejects a password without a letter', () => {
        const result = validateRegistrationInput({
            displayName: 'Test User',
            email: 'test@example.com',
            password: '12345678',
        });

        assert.deepEqual(result.errors, [
            'password must contain at least one letter and one number',
        ]);
    });

    test('rejects a password without a number', () => {
        const result = validateRegistrationInput({
            displayName: 'Test User',
            email: 'test@example.com',
            password: 'PasswordOnly',
        });

        assert.deepEqual(result.errors, [
            'password must contain at least one letter and one number',
        ]);
    });

    test('rejects a missing display name', () => {
        const result = validateRegistrationInput({
            email: 'test@example.com',
            password: 'StrongPassword123',
        });

        assert.deepEqual(result.errors, [
            'displayName is required',
        ]);
    });
});

describe('validateLoginInput', () => {
    test('accepts valid login data and normalizes email', () => {
        const result = validateLoginInput({
            email: '  TEST@EXAMPLE.COM  ',
            password: 'password123',
        });

        assert.deepEqual(result.errors, []);

        assert.deepEqual(result.value, {
            email: 'test@example.com',
            password: 'password123',
        });
    });

    test('rejects a missing email and password', () => {
        const result = validateLoginInput({});

        assert.deepEqual(result.errors, [
            'email is required',
            'password is required',
        ]);
    });

    test('rejects an invalid login email', () => {
        const result = validateLoginInput({
            email: 'invalid-email',
            password: 'password123',
        });

        assert.deepEqual(result.errors, [
            'email is invalid',
        ]);
    });

    test('allows a non-empty short password to reach authentication', () => {
        const result = validateLoginInput({
            email: 'test@example.com',
            password: 'wrong',
        });

        assert.deepEqual(result.errors, []);
    });
});

describe('validatePasswordResetRequestInput', () => {
    test('accepts and normalizes a valid email', () => {
        const result = validatePasswordResetRequestInput({
            email: '  TEST@EXAMPLE.COM  ',
        });

        assert.deepEqual(result, {
            errors: [],
            value: {
                email: 'test@example.com',
            },
        });
    });

    test('rejects an invalid email', () => {
        const result = validatePasswordResetRequestInput({
            email: 'invalid-email',
        });

        assert.deepEqual(result.errors, [
            'email is invalid',
        ]);
    });
});

describe('validatePasswordResetConfirmationInput', () => {
    test('accepts a valid token and password', () => {
        const result =
            validatePasswordResetConfirmationInput({
                token: 'A'.repeat(64),
                password: 'Replacement123',
            });

        assert.deepEqual(result, {
            errors: [],
            value: {
                token: 'a'.repeat(64),
                password: 'Replacement123',
            },
        });
    });

    test('rejects an invalid token and short password', () => {
        const result =
            validatePasswordResetConfirmationInput({
                token: 'invalid-token',
                password: 'short',
            });

        assert.deepEqual(result.errors, [
            'token is invalid',
            'password must contain at least 8 characters',
        ]);
    });

    test('rejects a password without a number', () => {
        const result =
            validatePasswordResetConfirmationInput({
                token: 'a'.repeat(64),
                password: 'PasswordOnly',
            });

        assert.deepEqual(result.errors, [
            'password must contain at least one letter and one number',
        ]);
    });
});

describe('validateAccountDeletionInput', () => {
    test('accepts a non-empty current password without applying new-password rules', () => {
        const result = validateAccountDeletionInput({
            password: 'current password',
        });

        assert.deepEqual(result, {
            errors: [],
            value: {
                password: 'current password',
            },
        });
    });

    test('rejects a missing password', () => {
        const result = validateAccountDeletionInput({});

        assert.deepEqual(result.errors, [
            'password is required',
        ]);
    });

    test('rejects a password longer than 72 characters', () => {
        const result = validateAccountDeletionInput({
            password: 'a'.repeat(73),
        });

        assert.deepEqual(result.errors, [
            'password must not exceed 72 characters',
        ]);
    });
});