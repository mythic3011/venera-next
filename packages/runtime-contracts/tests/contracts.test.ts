import { describe, expect, it } from "vitest";

import {
  API_ROUTES,
  apiErrorSchema,
  createComicResponseSchema,
  RUNTIME_ERROR_TABLE,
  runtimeSummarySchema,
} from "../src/index.js";

describe("runtime contracts", () => {
  it("exports the canonical API routes", () => {
    expect(API_ROUTES).toEqual({
      runtimeHealth: "/api/runtime/health",
      runtimeOpen: "/api/runtime/open",
      runtimeClose: "/api/runtime/close",
      createComic: "/api/comics",
    });
  });

  it("keeps the closed runtime error table exact", () => {
    expect(RUNTIME_ERROR_TABLE).toEqual({
      VALIDATION_FAILED: {
        status: 400,
        message: "Request validation failed.",
      },
      IDEMPOTENCY_KEY_PAYLOAD_MISMATCH: {
        status: 409,
        message: "Idempotency key was already used with different input.",
      },
      RUNTIME_NOT_OPEN: {
        status: 409,
        message: "Runtime instance is not open.",
      },
      RUNTIME_UNAVAILABLE: {
        status: 503,
        message: "Runtime is unavailable.",
      },
      RUNTIME_SHUTTING_DOWN: {
        status: 503,
        message: "Runtime is shutting down.",
      },
      INTERNAL: {
        status: 500,
        message: "Internal server error.",
      },
    });
  });

  it("accepts a demo-memory runtime summary and rejects persistence drift", () => {
    expect(runtimeSummarySchema.parse({
      mode: "demo-memory",
      state: "open",
      persistence: {
        kind: "memory",
        persisted: false,
        notice: "not-persisted",
      },
    })).toMatchObject({
      mode: "demo-memory",
      state: "open",
    });

    expect(() => runtimeSummarySchema.parse({
      mode: "demo-memory",
      state: "open",
      persistence: {
        kind: "memory",
        persisted: true,
        notice: "not-persisted",
      },
    })).toThrow();
  });

  it("rejects comic responses that leak non-JSON runtime objects or extra fields", () => {
    expect(() => createComicResponseSchema.parse({
      comic: {
        id: "ce9782c7-ff6b-4af3-a631-194a11468b8c",
        normalizedTitle: "demo comic",
        originHint: "unknown",
        createdAt: new Date(),
        updatedAt: "2026-05-07T00:00:00.000Z",
      },
      metadata: {
        comicId: "ce9782c7-ff6b-4af3-a631-194a11468b8c",
        title: "Demo Comic",
        createdAt: "2026-05-07T00:00:00.000Z",
        updatedAt: "2026-05-07T00:00:00.000Z",
      },
      primaryTitle: {
        id: "9cb74606-b305-4d19-9c57-914a8efca83f",
        comicId: "ce9782c7-ff6b-4af3-a631-194a11468b8c",
        title: "Demo Comic",
        normalizedTitle: "demo comic",
        titleKind: "primary",
        createdAt: "2026-05-07T00:00:00.000Z",
      },
      databasePath: ":memory:",
    })).toThrow();
  });

  it("rejects error envelopes that carry leaked runtime internals", () => {
    expect(() => apiErrorSchema.parse({
      error: {
        code: "INTERNAL",
        message: "Internal server error.",
        details: {
          databasePath: ":memory:",
        },
      },
    })).toThrow();
  });
});
