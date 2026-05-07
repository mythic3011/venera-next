import { describe, expect, it } from "vitest";

import {
  API_ERROR_CODES,
  ApiErrorCodeSchema,
  ApiErrorResponseSchema,
  COMICS_CREATE_PATH,
  CreateComicRequestSchema,
  CreateComicResponseSchema,
  RUNTIME_CLOSE_PATH,
  RUNTIME_HEALTH_PATH,
  RUNTIME_OPEN_PATH,
  RuntimeCloseRoute,
  RuntimeHealthRoute,
  RuntimeOpenRoute,
  RuntimeSummarySchema,
  mapCreatedCanonicalComicToDto,
} from "../src/index.js";

describe("@venera/runtime-contracts", () => {
  it("keeps the public API error code table closed", () => {
    expect(API_ERROR_CODES).toEqual([
      "VALIDATION_FAILED",
      "IDEMPOTENCY_KEY_PAYLOAD_MISMATCH",
      "RUNTIME_NOT_OPEN",
      "RUNTIME_UNAVAILABLE",
      "RUNTIME_SHUTTING_DOWN",
      "INTERNAL",
    ]);
    expect(ApiErrorCodeSchema.options).toEqual(API_ERROR_CODES);
  });

  it("never accepts internal error details on the public error response", () => {
    expect(ApiErrorResponseSchema.safeParse({
      error: {
        code: "INTERNAL",
        message: "Something failed.",
      },
    }).success).toBe(true);

    expect(ApiErrorResponseSchema.safeParse({
      error: {
        code: "IDEMPOTENCY_CONFLICT",
        message: "Internal code leaked.",
      },
    }).success).toBe(false);

    expect(ApiErrorResponseSchema.safeParse({
      error: {
        code: "INTERNAL",
        message: "Something failed.",
        details: {
          internal: true,
        },
      },
    }).success).toBe(false);
  });

  it("defines runtime summary DTOs that expose demo-memory and non-persisted state", () => {
    expect(RuntimeSummarySchema.parse({
      mode: "demo-memory",
      persisted: false,
      persistence: "not persisted",
    })).toEqual({
      mode: "demo-memory",
      persisted: false,
      persistence: "not persisted",
    });

    expect(RuntimeSummarySchema.safeParse({
      mode: "sqlite",
      persisted: true,
      persistence: "persisted",
    }).success).toBe(false);
  });

  it("exports canonical health/open/close route paths", () => {
    expect(RUNTIME_HEALTH_PATH).toBe("/api/runtime/health");
    expect(RUNTIME_OPEN_PATH).toBe("/api/runtime/open");
    expect(RUNTIME_CLOSE_PATH).toBe("/api/runtime/close");
    expect(COMICS_CREATE_PATH).toBe("/api/comics");

    expect(RuntimeHealthRoute.method).toBe("GET");
    expect(RuntimeHealthRoute.path).toBe(RUNTIME_HEALTH_PATH);
    expect(RuntimeOpenRoute.method).toBe("POST");
    expect(RuntimeOpenRoute.path).toBe(RUNTIME_OPEN_PATH);
    expect(RuntimeCloseRoute.method).toBe("POST");
    expect(RuntimeCloseRoute.path).toBe(RUNTIME_CLOSE_PATH);
  });

  it("validates comic creation requests as strict JSON-safe input", () => {
    expect(CreateComicRequestSchema.parse({
      title: "  Dorohedoro  ",
      description: "  grime  ",
      authorName: "  Q Hayashida  ",
      originHint: "remote",
      idempotencyKey: "  create-comic-1  ",
    })).toEqual({
      title: "Dorohedoro",
      description: "grime",
      authorName: "Q Hayashida",
      originHint: "remote",
      idempotencyKey: "create-comic-1",
    });

    expect(CreateComicRequestSchema.safeParse({
      title: "   ",
    }).success).toBe(false);

    expect(CreateComicRequestSchema.safeParse({
      title: "Dorohedoro",
      extra: true,
    }).success).toBe(false);
  });

  it("maps CreatedCanonicalComic-shaped data into ISO-string DTOs", () => {
    const created: Parameters<typeof mapCreatedCanonicalComicToDto>[0] = {
      comic: {
        id: "comic_123",
        normalizedTitle: "dorohedoro",
        originHint: "remote",
        createdAt: new Date("2026-05-07T00:00:00.000Z"),
        updatedAt: new Date("2026-05-07T01:00:00.000Z"),
      },
      metadata: {
        comicId: "comic_123",
        title: "Dorohedoro",
        description: "sorcerers and grime",
        authorName: "Q Hayashida",
        metadata: {
          tags: ["seinen", "dark-fantasy"],
          stats: {
            volumes: 23,
          },
        },
        createdAt: new Date("2026-05-07T00:00:00.000Z"),
        updatedAt: new Date("2026-05-07T01:00:00.000Z"),
      },
      primaryTitle: {
        id: "title_123",
        comicId: "comic_123",
        title: "Dorohedoro",
        normalizedTitle: "dorohedoro",
        titleKind: "primary",
        createdAt: new Date("2026-05-07T00:00:00.000Z"),
      },
    };

    const dto = mapCreatedCanonicalComicToDto(created);

    expect(dto).toEqual({
      comic: {
        id: "comic_123",
        normalizedTitle: "dorohedoro",
        originHint: "remote",
        createdAt: "2026-05-07T00:00:00.000Z",
        updatedAt: "2026-05-07T01:00:00.000Z",
      },
      metadata: {
        comicId: "comic_123",
        title: "Dorohedoro",
        description: "sorcerers and grime",
        authorName: "Q Hayashida",
        metadata: {
          tags: ["seinen", "dark-fantasy"],
          stats: {
            volumes: 23,
          },
        },
        createdAt: "2026-05-07T00:00:00.000Z",
        updatedAt: "2026-05-07T01:00:00.000Z",
      },
      primaryTitle: {
        id: "title_123",
        comicId: "comic_123",
        title: "Dorohedoro",
        normalizedTitle: "dorohedoro",
        titleKind: "primary",
        createdAt: "2026-05-07T00:00:00.000Z",
      },
    });

    expect(CreateComicResponseSchema.parse(dto)).toEqual(dto);

    expect(CreateComicResponseSchema.safeParse({
      comic: {
        id: "comic_123",
        normalizedTitle: "dorohedoro",
        originHint: "remote",
        createdAt: new Date("2026-05-07T00:00:00.000Z"),
        updatedAt: "2026-05-07T01:00:00.000Z",
      },
      metadata: {
        comicId: "comic_123",
        title: "Dorohedoro",
        createdAt: "2026-05-07T00:00:00.000Z",
        updatedAt: "2026-05-07T01:00:00.000Z",
      },
      primaryTitle: {
        id: "title_123",
        comicId: "comic_123",
        title: "Dorohedoro",
        normalizedTitle: "dorohedoro",
        titleKind: "primary",
        createdAt: "2026-05-07T00:00:00.000Z",
      },
    }).success).toBe(false);
  });
});
