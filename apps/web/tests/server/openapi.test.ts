import { describe, expect, it } from "vitest";

import { createWebServer } from "../../src/server/create-web-server.js";

describe("openapi routes", () => {
  it("publishes the canonical route set", async () => {
    const server = createWebServer();
    const response = await server.app.request("http://local.test/api/openapi.json");
    const document = await response.json() as {
      paths: Record<string, unknown>;
    };

    expect(Object.keys(document.paths).sort()).toEqual([
      "/api/comics",
      "/api/runtime/close",
      "/api/runtime/health",
      "/api/runtime/open",
    ]);
  });
});
