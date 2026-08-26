const { after, describe, test } = require("node:test");
const assert = require("node:assert/strict");
const { randomUUID } = require("node:crypto");

require("dotenv").config({
  quiet: true,
});

const { createAccessToken } = require("../src/auth_token");
const pool = require("../src/database");

const baseUrl = process.env.API_BASE_URL || "http://127.0.0.1:3000";
after(async () => {
  await pool.end();
});

const accessToken = createAccessToken(1);

function headersForToken(token, extraHeaders = {}) {
  return {
    Authorization: `Bearer ${token}`,
    ...extraHeaders,
  };
}

function authenticatedHeaders(extraHeaders = {}) {
  return headersForToken(accessToken, extraHeaders);
}

async function createTestAccount(label) {
  const registrationResponse = await fetch(`${baseUrl}/auth/register`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json; charset=utf-8",
    },
    body: JSON.stringify({
      displayName: `Isolation User ${label}`,
      email: `thought-isolation-${label}-${randomUUID()}@example.com`,
      password: "Isolation123!",
    }),
  });

  assert.equal(registrationResponse.status, 201);

  const user = await registrationResponse.json();

  return {
    user,
    accessToken: createAccessToken(user.id),
  };
}

describe("Thought API", () => {
  test("rejects unauthenticated thought requests", async () => {
    const responses = await Promise.all([
      fetch(`${baseUrl}/thoughts`),

      fetch(`${baseUrl}/thoughts`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json; charset=utf-8",
        },
        body: JSON.stringify({}),
      }),

      fetch(`${baseUrl}/thoughts/0`, {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json; charset=utf-8",
        },
        body: JSON.stringify({}),
      }),

      fetch(`${baseUrl}/thoughts/0`, {
        method: "DELETE",
      }),
    ]);

    for (const response of responses) {
      assert.equal(response.status, 401);
    }
  });

  test("keeps thought lists isolated between two users", async () => {
    let accountA = null;
    let accountB = null;

    try {
      accountA = await createTestAccount("A");
      accountB = await createTestAccount("B");

      const createResponse = await fetch(`${baseUrl}/thoughts`, {
        method: "POST",
        headers: headersForToken(accountA.accessToken, {
          "Content-Type": "application/json; charset=utf-8",
        }),
        body: JSON.stringify({
          title: "User A private thought",
          content: "This thought must not be visible to User B.",
          tag: "Test",
        }),
      });

      assert.equal(createResponse.status, 201);

      const createdThought = await createResponse.json();

      const accountBListResponse = await fetch(`${baseUrl}/thoughts`, {
        headers: headersForToken(accountB.accessToken),
      });

      assert.equal(accountBListResponse.status, 200);

      const accountBThoughts = await accountBListResponse.json();

      assert.equal(
        accountBThoughts.some(
          (thought) => String(thought.id) === String(createdThought.id),
        ),
        false,
      );

      const accountBUpdateResponse = await fetch(
        `${baseUrl}/thoughts/${createdThought.id}`,
        {
          method: "PATCH",
          headers: headersForToken(accountB.accessToken, {
            "Content-Type": "application/json; charset=utf-8",
          }),
          body: JSON.stringify({
            title: "Changed by User B",
            content: "User B must not be able to change this.",
            tag: "Attack",
            isFavorite: true,
          }),
        },
      );

      assert.equal(accountBUpdateResponse.status, 404);

      const accountBDeleteResponse = await fetch(
        `${baseUrl}/thoughts/${createdThought.id}`,
        {
          method: "DELETE",
          headers: headersForToken(accountB.accessToken),
        },
      );

      assert.equal(accountBDeleteResponse.status, 404);

      const accountAListResponse = await fetch(`${baseUrl}/thoughts`, {
        headers: headersForToken(accountA.accessToken),
      });

      assert.equal(accountAListResponse.status, 200);

      const accountAThoughts = await accountAListResponse.json();

      const preservedThought = accountAThoughts.find(
        (thought) => String(thought.id) === String(createdThought.id),
      );

      assert.notEqual(preservedThought, undefined);
      assert.equal(preservedThought.title, "User A private thought");
      assert.equal(preservedThought.isFavorite, false);
    } finally {
      const userIds = [accountA?.user.id, accountB?.user.id].filter(Boolean);

      if (userIds.length > 0) {
        await pool.query("DELETE FROM users WHERE id = ANY($1::bigint[])", [
          userIds,
        ]);
      }
    }
  });

  test("creates, reads, updates and deletes a thought", async () => {
    let createdId = null;

    try {
      const uniqueTitle = `Integration Test ${Date.now()}`;

      const createResponse = await fetch(`${baseUrl}/thoughts`, {
        method: "POST",
        headers: authenticatedHeaders({
          "Content-Type": "application/json; charset=utf-8",
        }),
        body: JSON.stringify({
          title: uniqueTitle,
          content: "Created by the API integration test.",
          tag: "Test",
        }),
      });

      assert.equal(createResponse.status, 201);

      const createdThought = await createResponse.json();
      createdId = String(createdThought.id);

      assert.equal(createdThought.title, uniqueTitle);
      assert.equal(createdThought.isFavorite, false);

      const listResponse = await fetch(`${baseUrl}/thoughts`, {
        headers: authenticatedHeaders(),
      });

      assert.equal(listResponse.status, 200);

      const thoughts = await listResponse.json();

      assert.ok(thoughts.some((thought) => String(thought.id) === createdId));

      const updateResponse = await fetch(`${baseUrl}/thoughts/${createdId}`, {
        method: "PATCH",
        headers: authenticatedHeaders({
          "Content-Type": "application/json; charset=utf-8",
        }),
        body: JSON.stringify({
          title: `${uniqueTitle} Updated`,
          content: "Updated by the API integration test.",
          tag: "Integration",
          isFavorite: true,
        }),
      });

      assert.equal(updateResponse.status, 200);

      const updatedThought = await updateResponse.json();

      assert.equal(updatedThought.title, `${uniqueTitle} Updated`);
      assert.equal(updatedThought.tag, "Integration");
      assert.equal(updatedThought.isFavorite, true);

      const deleteResponse = await fetch(`${baseUrl}/thoughts/${createdId}`, {
        method: "DELETE",
        headers: authenticatedHeaders(),
      });

      assert.equal(deleteResponse.status, 204);

      const finalListResponse = await fetch(`${baseUrl}/thoughts`, {
        headers: authenticatedHeaders(),
      });

      assert.equal(finalListResponse.status, 200);

      const finalThoughts = await finalListResponse.json();

      assert.equal(
        finalThoughts.some((thought) => String(thought.id) === createdId),
        false,
      );

      createdId = null;
    } finally {
      if (createdId !== null) {
        await fetch(`${baseUrl}/thoughts/${createdId}`, {
          method: "DELETE",
          headers: authenticatedHeaders(),
        });
      }
    }
  });

  test("rejects invalid thought data", async () => {
    const response = await fetch(`${baseUrl}/thoughts`, {
      method: "POST",
      headers: authenticatedHeaders({
        "Content-Type": "application/json; charset=utf-8",
      }),
      body: JSON.stringify({
        title: "",
        content: "",
        tag: "",
      }),
    });

    assert.equal(response.status, 400);

    const responseBody = await response.json();

    assert.equal(responseBody.message, "Invalid thought data");

    assert.ok(responseBody.errors.includes("content is required"));

    assert.ok(responseBody.errors.includes("tag is required"));
  });
});
