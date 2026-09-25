const {
    after,
    before,
    test,
} = require('node:test');

const assert = require('node:assert/strict');

const originalHstsValue =
    process.env.ENABLE_HSTS;

process.env.ENABLE_HSTS = 'true';

const app = require('../src/server');

let server;
let baseUrl;

before(async () => {
    await new Promise((resolve, reject) => {
        server = app.listen(
            0,
            '127.0.0.1',
            () => {
                const address = server.address();

                baseUrl =
                    `http://127.0.0.1:${address.port}`;

                resolve();
            },
        );

        server.on('error', reject);
    });
});

after(async () => {
    await new Promise((resolve, reject) => {
        server.close((error) => {
            if (error !== undefined) {
                reject(error);
                return;
            }

            resolve();
        });
    });

    if (originalHstsValue === undefined) {
        delete process.env.ENABLE_HSTS;
    } else {
        process.env.ENABLE_HSTS =
            originalHstsValue;
    }
});

test('sets HSTS when explicitly enabled', async () => {
    const response = await fetch(`${baseUrl}/health`);

    assert.equal(response.status, 200);
    assert.equal(
        response.headers.get(
            'strict-transport-security',
        ),
        'max-age=31536000',
    );
});
