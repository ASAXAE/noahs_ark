const test = require('node:test');
const assert = require('node:assert/strict');

const {
    validateThoughtInput,
} = require('../src/thought_validation');

test('accepts valid thought data and trims title and tag', () => {
    const result = validateThoughtInput({
        title: '  A small step  ',
        content: 'Keep learning one layer at a time.',
        tag: '  growth  ',
    });

    assert.deepEqual(result.errors, []);
    assert.deepEqual(result.value, {
        title: 'A small step',
        content: 'Keep learning one layer at a time.',
        tag: 'growth',
    });
});

test('rejects content that only contains whitespace', () => {
    const result = validateThoughtInput({
        title: 'Empty note',
        content: '   ',
        tag: 'learning',
    });

    assert.deepEqual(result.errors, ['content is required']);
});

test('rejects a title longer than 50 characters', () => {
    const result = validateThoughtInput({
        title: 'a'.repeat(51),
        content: 'Valid content',
        tag: 'learning',
    });

    assert.deepEqual(
        result.errors,
        ['title must not exceed 50 characters'],
    );
});

test('rejects a missing tag', () => {
    const result = validateThoughtInput({
        title: 'A thought',
        content: 'Valid content',
    });

    assert.deepEqual(result.errors, ['tag is required']);
});
