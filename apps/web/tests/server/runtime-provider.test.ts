import { describe, expect, it, vi } from "vitest";

import { createRuntimeProvider } from "../../src/provider/runtime-provider.js";

function createFakeRuntime() {
  return {
    close: vi.fn(),
    useCases: {
      createCanonicalComic: {
        execute: vi.fn(),
      },
    },
  };
}

describe("runtime provider", () => {
  it("deduplicates concurrent open calls", async () => {
    const runtime = createFakeRuntime();
    const createRuntime = vi.fn(async () => runtime);
    const provider = createRuntimeProvider({ createRuntime });

    const [first, second] = await Promise.all([
      provider.open(),
      provider.open(),
    ]);

    expect(createRuntime).toHaveBeenCalledTimes(1);
    expect(first.state).toBe("open");
    expect(second.state).toBe("open");
  });

  it("closes the open runtime", async () => {
    const runtime = createFakeRuntime();
    const provider = createRuntimeProvider({
      createRuntime: async () => runtime,
    });

    await provider.open();
    const result = await provider.close();

    expect(runtime.close).toHaveBeenCalledTimes(1);
    expect(result.state).toBe("closed");
  });

  it("waits for in-flight work during shutdown", async () => {
    let resolveOperation: (() => void) | null = null;
    const runtime = createFakeRuntime();
    runtime.useCases.createCanonicalComic.execute.mockImplementation(async () => {
      await new Promise<void>((resolve) => {
        resolveOperation = resolve;
      });

      return {
        ok: true as const,
        value: {
          comic: {
            id: "1db55809-a5fe-421d-98ef-636fe5036ff5",
            normalizedTitle: "demo",
            originHint: "unknown" as const,
            createdAt: new Date("2026-05-07T00:00:00.000Z"),
            updatedAt: new Date("2026-05-07T00:00:00.000Z"),
          },
          metadata: {
            comicId: "1db55809-a5fe-421d-98ef-636fe5036ff5",
            title: "Demo",
            createdAt: new Date("2026-05-07T00:00:00.000Z"),
            updatedAt: new Date("2026-05-07T00:00:00.000Z"),
          },
          primaryTitle: {
            id: "0fe3289e-00ce-4a76-aa07-ffae50d3d1f9",
            comicId: "1db55809-a5fe-421d-98ef-636fe5036ff5",
            title: "Demo",
            normalizedTitle: "demo",
            titleKind: "primary" as const,
            createdAt: new Date("2026-05-07T00:00:00.000Z"),
          },
        },
      };
    });

    const provider = createRuntimeProvider({
      createRuntime: async () => runtime,
    });
    await provider.open();

    const operation = provider.withRuntime((openedRuntime) => {
      return openedRuntime.useCases.createCanonicalComic.execute({
        title: "Demo",
      });
    });
    const shutdown = provider.shutdown();

    expect(runtime.close).toHaveBeenCalledTimes(0);

    resolveOperation?.();
    await operation;
    await shutdown;

    expect(runtime.close).toHaveBeenCalledTimes(1);
    expect(provider.getSummary().state).toBe("closed");
  });

  it("rejects new work during shutdown", async () => {
    let resolveOperation: (() => void) | null = null;
    const runtime = createFakeRuntime();
    runtime.useCases.createCanonicalComic.execute.mockImplementation(async () => {
      await new Promise<void>((resolve) => {
        resolveOperation = resolve;
      });
      return {
        ok: true as const,
        value: {
          comic: {
            id: "1db55809-a5fe-421d-98ef-636fe5036ff5",
            normalizedTitle: "demo",
            originHint: "unknown" as const,
            createdAt: new Date("2026-05-07T00:00:00.000Z"),
            updatedAt: new Date("2026-05-07T00:00:00.000Z"),
          },
          metadata: {
            comicId: "1db55809-a5fe-421d-98ef-636fe5036ff5",
            title: "Demo",
            createdAt: new Date("2026-05-07T00:00:00.000Z"),
            updatedAt: new Date("2026-05-07T00:00:00.000Z"),
          },
          primaryTitle: {
            id: "0fe3289e-00ce-4a76-aa07-ffae50d3d1f9",
            comicId: "1db55809-a5fe-421d-98ef-636fe5036ff5",
            title: "Demo",
            normalizedTitle: "demo",
            titleKind: "primary" as const,
            createdAt: new Date("2026-05-07T00:00:00.000Z"),
          },
        },
      };
    });
    const provider = createRuntimeProvider({
      createRuntime: async () => runtime,
    });

    await provider.open();
    const inFlight = provider.withRuntime((openedRuntime) => {
      return openedRuntime.useCases.createCanonicalComic.execute({
        title: "Demo",
      });
    });
    const shutdown = provider.shutdown();

    await expect(provider.withRuntime(async () => undefined)).rejects.toMatchObject({
      code: "RUNTIME_SHUTTING_DOWN",
    });

    resolveOperation?.();
    await inFlight;
    await shutdown;
  });
});
