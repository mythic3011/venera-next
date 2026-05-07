import { describe, expect, it } from "vitest";

import { createApiClient } from "../../src/client/api/client.js";
import { createWebServer } from "../../src/server/create-web-server.js";

function bridgeFetch(server: ReturnType<typeof createWebServer>["app"]): typeof fetch {
  return async (input, init) => {
    if (input instanceof Request) {
      return server.fetch(input);
    }

    return server.request(input.toString(), init);
  };
}

describe("web shell integration", () => {
  it("creates a comic through client -> hono -> adapter -> runtime/core", async () => {
    const server = createWebServer();
    const client = createApiClient({
      baseUrl: "http://local.test",
      fetch: bridgeFetch(server.app),
    });

    await client.openRuntime();
    const response = await client.createComic({
      title: "End To End Comic",
      description: "smoke",
      authorName: "Alvin",
      idempotencyKey: "end-to-end-stable-key",
    });

    expect(response.metadata.title).toBe("End To End Comic");
    expect(response.comic.id).toMatch(
      /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i,
    );
  });

  it("returns one comic for concurrent identical idempotent requests", async () => {
    const server = createWebServer();
    const client = createApiClient({
      baseUrl: "http://local.test",
      fetch: bridgeFetch(server.app),
    });

    await client.openRuntime();

    const [first, second] = await Promise.all([
      client.createComic({
        title: "Concurrent Comic",
        idempotencyKey: "concurrent-stable-key",
      }),
      client.createComic({
        title: "Concurrent Comic",
        idempotencyKey: "concurrent-stable-key",
      }),
    ]);

    expect(first.comic.id).toBe(second.comic.id);
  });
});
