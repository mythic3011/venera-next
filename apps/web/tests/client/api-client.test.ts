import { describe, expect, it } from "vitest";

import { createApiClient } from "../../src/client/api/client.js";

describe("api client", () => {
  it("validates successful runtime payloads", async () => {
    const client = createApiClient({
      baseUrl: "http://example.test",
      fetch: async () => new Response(JSON.stringify({
        runtime: {
          mode: "demo-memory",
          state: "open",
          persistence: {
            kind: "memory",
            persisted: false,
            notice: "not-persisted",
          },
        },
      })),
    });

    const response = await client.getRuntimeHealth();
    expect(response.runtime.state).toBe("open");
  });

  it("rejects malformed success payloads", async () => {
    const client = createApiClient({
      fetch: async () => new Response(JSON.stringify({
        runtime: {
          mode: "demo-memory",
        },
      })),
    });

    await expect(client.getRuntimeHealth()).rejects.toThrow(
      "API returned an invalid success payload.",
    );
  });

  it("surfaces safe API errors", async () => {
    const client = createApiClient({
      fetch: async () => new Response(JSON.stringify({
        error: {
          code: "RUNTIME_NOT_OPEN",
          message: "Runtime instance is not open.",
        },
      }), {
        status: 409,
      }),
    });

    await expect(client.createComic({
      title: "Demo Comic",
      idempotencyKey: "stable-key",
    })).rejects.toMatchObject({
      message: "Runtime instance is not open.",
      status: 409,
    });
  });
});
