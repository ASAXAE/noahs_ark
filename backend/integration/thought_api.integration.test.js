const { describe, test } = require("node:test");
const assert = require("node:assert/strict");

require("dotenv").config({
  quiet: true,
});

const { createAccessToken } = require("../src/auth_token");

const baseUrl = process.env.API_BASE_URL || "http://127.0.0.1:3000";

const accessToken = createAccessToken(1);

function authenticatedHeaders(extraHeaders = {}) {
  return {
    Authorization: `Bearer ${accessToken}`,
    ...extraHeaders,
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
