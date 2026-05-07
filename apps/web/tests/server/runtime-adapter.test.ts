import { describe, expect, it } from "vitest";

import { createRuntimeAdapter } from "../../src/adapter/runtime-adapter.js";
import { createRuntimeProvider } from "../../src/provider/runtime-provider.js";

function createRuntimeFactory() {
  return async () => {
    const runtime = await import("@venera/runtime-core");
    return runtime.createCoreRuntime({
      databasePath: ":memory:",
    });
  };
}

describe("runtime adapter", () => {
  it("reports runtime health", () => {
    const adapter = createRuntimeAdapter({
      provider: createRuntimeProvider({
        createRuntime: createRuntimeFactory(),
      }),
    });

    expect(adapter.getHealth().runtime).toMatchObject({
      mode: "demo-memory",
      state: "closed",
    });
  });

  it("creates and replays a comic with a stable idempotency key", async () => {
    const provider = createRuntimeProvider({
      createRuntime: createRuntimeFactory(),
    });
    const adapter = createRuntimeAdapter({ provider });

    await adapter.openRuntime();
    const first = await adapter.createComic({
      title: "Demo Comic",
      idempotencyKey: "stable-key",
    });
    const second = await adapter.createComic({
      title: "Demo Comic",
      idempotencyKey: "stable-key",
    });

    expect(second).toEqual(first);
  });

  it("maps idempotency conflicts to the closed safe error table", async () => {
    const provider = createRuntimeProvider({
      createRuntime: createRuntimeFactory(),
    });
    const adapter = createRuntimeAdapter({ provider });

    await adapter.openRuntime();
    await adapter.createComic({
      title: "Demo Comic",
      idempotencyKey: "stable-key",
    });

    await expect(adapter.createComic({
      title: "Different Demo Comic",
      idempotencyKey: "stable-key",
    })).rejects.toMatchObject({
      code: "IDEMPOTENCY_KEY_PAYLOAD_MISMATCH",
      message: "Idempotency key was already used with different input.",
      status: 409,
    });
  });
});
