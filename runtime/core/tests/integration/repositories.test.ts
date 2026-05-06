import { describe, expect, it } from "vitest";
import { sql } from "kysely";

import {
  CREATE_CANONICAL_COMIC_OPERATION_NAME,
  CREATED_CANONICAL_COMIC_RESULT_TYPE,
  IDEMPOTENCY_RESULT_SCHEMA_VERSION,
  parseIdempotencyKey,
  parseInputHash,
} from "../../src/domain/idempotency.js";
import type { IdempotencyKey, InputHash } from "../../src/domain/idempotency.js";
import type { JsonObject } from "../../src/shared/json.js";
import { createTestRuntime, insertComicFixture } from "../support/test-runtime.js";

function expectIdempotencyKey(value: string): IdempotencyKey {
  const parsed = parseIdempotencyKey(value);
  expect(parsed.ok).toBe(true);
  if (!parsed.ok) {
    throw parsed.error;
  }

  return parsed.value;
}

function expectInputHash(value: string): InputHash {
  const parsed = parseInputHash(value);
  expect(parsed.ok).toBe(true);
  if (!parsed.ok) {
    throw parsed.error;
  }

  return parsed.value;
}

describe("sqlite repositories", () => {
  it("returns domain-shaped objects instead of db row shapes", async () => {
    const runtime = await createTestRuntime();

    try {
      const fixture = await insertComicFixture(runtime);

      const comic = await runtime.repositories.comics.getById(fixture.comicId as never);
      const chapter = await runtime.repositories.chapters.getById(fixture.chapterIds[0] as never);
      const page = await runtime.repositories.pages.getById(fixture.pageIds[0] as never);

      expect(comic.ok).toBe(true);
      expect(chapter.ok).toBe(true);
      expect(page.ok).toBe(true);

      if (comic.ok && comic.value) {
        expect("normalized_title" in comic.value).toBe(false);
        expect(comic.value.normalizedTitle).toBeTypeOf("string");
      }

      if (chapter.ok && chapter.value) {
        expect("chapter_kind" in chapter.value).toBe(false);
        expect(chapter.value.chapterKind).toBe("chapter");
      }

      if (page.ok && page.value) {
        expect("page_index" in page.value).toBe(false);
        expect(page.value.pageIndex).toBe(0);
      }
    } finally {
      runtime.close();
    }
  });

  it("lists all comics sharing the same normalized title", async () => {
    const runtime = await createTestRuntime();

    try {
      const first = await insertComicFixture(runtime, {
        comicId: "11111111-1111-4111-8111-111111111111",
        title: "Shared Title",
      });
      const second = await insertComicFixture(runtime, {
        comicId: "22222222-2222-4222-8222-222222222222",
        title: "Shared Title",
      });

      const comics = await runtime.repositories.comics.listByNormalizedTitle("shared title" as never);

      expect(comics.ok).toBe(true);
      if (comics.ok) {
        expect(comics.value.map((comic) => comic.id)).toEqual([
          first.comicId,
          second.comicId,
        ]);
        expect(comics.value.every((comic) => "normalized_title" in comic)).toBe(false);
      }
    } finally {
      runtime.close();
    }
  });

  it("persists diagnostics schemaVersion as 1.0.0", async () => {
    const runtime = await createTestRuntime();

    try {
      const recorded = await runtime.repositories.diagnosticsEvents.record({
        id: "33333333-3333-4333-8333-333333333333" as never,
        timestamp: new Date("2026-05-05T00:00:00.000Z"),
        level: "warn",
        channel: "reader.route",
        eventName: "reader.route.unresolved_target",
        payload: {
          reason: "test",
        },
      });

      expect(recorded.ok).toBe(true);
      if (recorded.ok) {
        expect(recorded.value.schemaVersion).toBe("1.0.0");
      }

      const queried = await runtime.repositories.diagnosticsEvents.query({
        channel: "reader.route",
      });

      expect(queried.ok).toBe(true);
      if (queried.ok) {
        expect(queried.value[0]?.schemaVersion).toBe("1.0.0");
      }

      const rows = await sql<{ schema_version: string }>`
        SELECT schema_version
        FROM diagnostics_events
        WHERE id = '33333333-3333-4333-8333-333333333333'
      `.execute(runtime.db);

      expect(rows.rows[0]?.schema_version).toBe("1.0.0");
    } finally {
      runtime.close();
    }
  });

  it("round-trips completed operation idempotency with a strict public DTO result", async () => {
    const runtime = await createTestRuntime();

    try {
      const reserved = await runtime.repositories.operationIdempotency.createInProgress({
        operationName: CREATE_CANONICAL_COMIC_OPERATION_NAME,
        idempotencyKey: expectIdempotencyKey("idem-key-1"),
        inputHash: expectInputHash("hash-1"),
        createdAt: new Date("2026-05-05T00:00:00.000Z"),
        updatedAt: new Date("2026-05-05T00:00:00.000Z"),
      });

      expect(reserved.ok).toBe(true);
      if (!reserved.ok) {
        return;
      }
      expect(reserved.value.status).toBe("in_progress");

      const completed = await runtime.repositories.operationIdempotency.markCompleted({
        operationName: CREATE_CANONICAL_COMIC_OPERATION_NAME,
        idempotencyKey: expectIdempotencyKey("idem-key-1"),
        inputHash: expectInputHash("hash-1"),
        resultType: CREATED_CANONICAL_COMIC_RESULT_TYPE,
        resultResourceId: "44444444-4444-4444-8444-444444444444" as never,
        resultSchemaVersion: IDEMPOTENCY_RESULT_SCHEMA_VERSION,
        updatedAt: new Date("2026-05-05T00:01:00.000Z"),
        resultJson: {
          comic: {
            id: "44444444-4444-4444-8444-444444444444" as never,
            normalizedTitle: "shared title",
            originHint: "local",
            createdAt: "2026-05-05T00:00:00.000Z",
            updatedAt: "2026-05-05T00:00:00.000Z",
          },
          metadata: {
            comicId: "44444444-4444-4444-8444-444444444444" as never,
            title: "Shared Title",
            createdAt: "2026-05-05T00:00:00.000Z",
            updatedAt: "2026-05-05T00:00:00.000Z",
          },
          primaryTitle: {
            id: "55555555-5555-4555-8555-555555555555",
            comicId: "44444444-4444-4444-8444-444444444444" as never,
            title: "Shared Title",
            normalizedTitle: "shared title",
            titleKind: "primary",
            createdAt: "2026-05-05T00:00:00.000Z",
          },
        },
      });

      expect(completed.ok).toBe(true);
      if (!completed.ok) {
        return;
      }
      expect(completed.value.status).toBe("completed");
      if (completed.value.status === "completed") {
        expect(completed.value.resultSchemaVersion).toBe("1.0.0");
      }

      const replay = await runtime.repositories.operationIdempotency.get({
        operationName: CREATE_CANONICAL_COMIC_OPERATION_NAME,
        idempotencyKey: expectIdempotencyKey("idem-key-1"),
      });

      expect(replay.ok).toBe(true);
      if (replay.ok && replay.value !== null && replay.value.status === "completed") {
        const resultJson = replay.value.resultJson as JsonObject;
        const comic = resultJson.comic as JsonObject;
        expect(comic.normalizedTitle).toBe("shared title");
        expect("normalized_title" in comic).toBe(false);
      }
    } finally {
      runtime.close();
    }
  });

  it("returns completed idempotency payloads as stored public projections", async () => {
    const runtime = await createTestRuntime();

    try {
      const now = new Date("2026-05-05T00:00:00.000Z").toISOString();
      await sql`
        INSERT INTO operation_idempotency (
          operation_name,
          idempotency_key,
          input_hash,
          status,
          result_type,
          result_resource_id,
          result_json,
          result_schema_version,
          created_at,
          updated_at
        )
        VALUES (
          'CreateCanonicalComic',
          'idem-bad',
          'hash-bad',
          'completed',
          'CreatedCanonicalComic',
          '44444444-4444-4444-8444-444444444444',
          ${JSON.stringify({
            comic: {
              id: "44444444-4444-4444-8444-444444444444",
              normalized_title: "bad shape",
              originHint: "local",
              createdAt: now,
              updatedAt: now,
            },
            metadata: {
              comicId: "44444444-4444-4444-8444-444444444444",
              createdAt: now,
              updatedAt: now,
            },
            primaryTitle: {
              id: "55555555-5555-4555-8555-555555555555",
              comicId: "44444444-4444-4444-8444-444444444444",
              title: "Bad Shape",
              normalizedTitle: "bad shape",
              titleKind: "primary",
              createdAt: now,
            },
          })},
          '1.0.0',
          ${now},
          ${now}
        )
      `.execute(runtime.db);

      const replay = await runtime.repositories.operationIdempotency.get({
        operationName: CREATE_CANONICAL_COMIC_OPERATION_NAME,
        idempotencyKey: expectIdempotencyKey("idem-bad"),
      });

      expect(replay.ok).toBe(true);
      if (replay.ok && replay.value !== null && replay.value.status === "completed") {
        expect(replay.value.resultJson).toBeDefined();
      }
    } finally {
      runtime.close();
    }
  });
});
