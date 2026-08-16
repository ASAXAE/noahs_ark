const { describe, test } = require('node:test');
const assert = require('node:assert/strict');

const {
    validateRegistrationInput,
} = require('../src/auth_validation');

describe('validateRegistrationInput', () => {
    test('accepts valid registration data and normalizes it', () => {
        const result = validateRegistrationInput({
            displayName: '  Test User  ',
            email: '  TEST@EXAMPLE.COM  ',
            password: 'password123',
        });

        assert.deepEqual(result.errors, []);

        assert.deepEqual(result.value, {
            displayName: 'Test User',
            email: 'test@example.com',
            password: 'password123',
        });
    });

    test('rejects an invalid email', () => {
        const result = validateRegistrationInput({
            displayName: 'Test User',
            email: 'invalid-email',
            password: 'password123',
        });

        assert.deepEqual(result.errors, [
            'email is invalid',
        ]);
    });

    test('rejects a password shorter than 8 characters', () => {
        const result = validateRegistrationInput({
            displayName: 'Test User',
            email: 'test@example.com',
            password: '1234567',
        });

        assert.deepEqual(result.errors, [
            'password must contain at least 8 characters',
        ]);
    });

    test('rejects a missing display name', () => {
        const result = validateRegistrationInput({
            email: 'test@example.com',
            password: 'password123',
        });

        assert.deepEqual(result.errors, [
            'displayName is required',
        ]);
    });
});