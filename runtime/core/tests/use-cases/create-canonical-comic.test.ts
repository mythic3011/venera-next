import { randomUUID } from "node:crypto";

import { describe, expect, it } from "vitest";
import { sql } from "kysely";

import { CreateCanonicalComic } from "../../src/application/create-canonical-comic.js";
import { createCoreError } from "../../src/shared/errors.js";
import { err } from "../../src/shared/result.js";
import { createTestRuntime } from "../support/test-runtime.js";

async function countComics(runtime: Awaited<ReturnType<typeof createTestRuntime>>): Promise<number> {
  const result = await sql<{ count: number }>`
    SELECT COUNT(*) AS count
    FROM comics
  `.execute(runtime.db);

  return Number(result.rows[0]?.count ?? 0);
}

async function readIdempotencyRows(
  runtime: Awaited<ReturnType<typeof createTestRuntime>>,
): Promise<readonly {
  operation_name: string;
  idempotency_key: string;
  input_hash: string;
  status: string;
  result_json: string | null;
}[]> {
  const result = await sql<{
    operation_name: string;
    idempotency_key: string;
    input_hash: string;
    status: string;
    result_json: string | null;
  }>`
    SELECT operation_name, idempotency_key, input_hash, status, result_json
    FROM operation_idempotency
    ORDER BY operation_name, idempotency_key
  `.execute(runtime.db);

  return result.rows;
}

describe("CreateCanonicalComic", () => {
  it("creates comic, metadata, and primary title transactionally", async () => {
    const runtime = await createTestRuntime();

    try {
      const result = await runtime.useCases.createCanonicalComic.execute({
        title: "Transactional Comic",
        description: "desc",
        authorName: "author",
      });

      expect(result.ok).toBe(true);
      if (!result.ok) {
        return;
      }

      const comic = await runtime.repositories.comics.getById(result.value.comic.id);
      const metadata = await runtime.repositories.comicMetadata.getByComicId(result.value.comic.id);
      const titles = await runtime.repositories.comicTitles.listByComic(result.value.comic.id);

      expect(comic.ok && comic.value !== null).toBe(true);
      expect(metadata.ok && metadata.value !== null).toBe(true);
      expect(titles.ok && titles.value.length).toBe(1);
      if (titles.ok) {
        expect(titles.value[0]?.titleKind).toBe("primary");
      }
    } finally {
      runtime.close();
    }
  });

  it("allows duplicate normalized titles when no idempotency key is provided", async () => {
    const runtime = await createTestRuntime();

    try {
      const first = await runtime.useCases.createCanonicalComic.execute({
        title: "Duplicate Title",
      });
      const second = await runtime.useCases.createCanonicalComic.execute({
        title: "Duplicate Title",
      });

      expect(first.ok).toBe(true);
      expect(second.ok).toBe(true);
      expect(await countComics(runtime)).toBe(2);
      if (first.ok && second.ok) {
        expect(first.value.comic.id).not.toBe(second.value.comic.id);
        expect(first.value.comic.normalizedTitle).toBe(second.value.comic.normalizedTitle);
      }
    } finally {
      runtime.close();
    }
  });

  it("creates new comics for repeated requests without an idempotency key", async () => {
    const runtime = await createTestRuntime();

    try {
      const input = {
        title: "Repeated Comic",
        description: "Same payload",
        authorName: "Creator",
      };

      const first = await runtime.useCases.createCanonicalComic.execute(input);
      const second = await runtime.useCases.createCanonicalComic.execute(input);

      expect(first.ok).toBe(true);
      expect(second.ok).toBe(true);
      expect(await countComics(runtime)).toBe(2);
      if (first.ok && second.ok) {
        expect(first.value.comic.id).not.toBe(second.value.comic.id);
      }
    } finally {
      runtime.close();
    }
  });

  it("replays a completed result for the same key and canonical input", async () => {
    const runtime = await createTestRuntime();

    try {
      const input = {
        title: "Replay Comic",
        description: "Stable payload",
        authorName: "Replay Author",
        idempotencyKey: "replay-key",
      };

      const first = await runtime.useCases.createCanonicalComic.execute(input);
      const second = await runtime.useCases.createCanonicalComic.execute(input);

      expect(first.ok).toBe(true);
      expect(second.ok).toBe(true);
      expect(await countComics(runtime)).toBe(1);
      if (first.ok && second.ok) {
        expect(second.value).toEqual(first.value);
      }

      const rows = await readIdempotencyRows(runtime);
      expect(rows).toHaveLength(1);
      expect(rows[0]?.operation_name).toBe("CreateCanonicalComic");
      expect(rows[0]?.status).toBe("completed");
      expect(rows[0]?.result_json).not.toBeNull();
    } finally {
      runtime.close();
    }
  });

  it("rejects malformed replay payloads with missing required fields or db-shaped snake_case fields", async () => {
    const runtime = await createTestRuntime();

    try {
      const input = {
        title: "Replay Mapper Comic",
        description: "Stable payload",
        idempotencyKey: "replay-mapper-bad",
      };

      const created = await runtime.useCases.createCanonicalComic.execute(input);
      expect(created.ok).toBe(true);

      const now = new Date("2026-05-05T00:00:00.000Z").toISOString();
      await sql`
        UPDATE operation_idempotency
        SET result_json = ${JSON.stringify({
          comic: {
            id: created.ok ? created.value.comic.id : "44444444-4444-4444-8444-444444444444",
            normalized_title: "replay mapper comic",
            originHint: "unknown",
            createdAt: now,
            updatedAt: now,
          },
          metadata: {
            comicId: created.ok ? created.value.comic.id : "44444444-4444-4444-8444-444444444444",
            createdAt: now,
            updatedAt: now,
          },
          primaryTitle: {
            id: "55555555-5555-4555-8555-555555555555",
            comicId: created.ok ? created.value.comic.id : "44444444-4444-4444-8444-444444444444",
            title: "Replay Mapper Comic",
            normalizedTitle: "replay mapper comic",
            titleKind: "primary",
            createdAt: now,
          },
        })}
        WHERE operation_name = 'CreateCanonicalComic'
          AND idempotency_key = 'replay-mapper-bad'
      `.execute(runtime.db);

      const replay = await runtime.useCases.createCanonicalComic.execute(input);
      expect(replay.ok).toBe(false);
      if (!replay.ok) {
        expect(replay.error.code).toBe("INTERNAL_ERROR");
      }
      expect(await countComics(runtime)).toBe(1);
    } finally {
      runtime.close();
    }
  });

  it("treats input object key order as hash-stable semantics", async () => {
    const runtime = await createTestRuntime();

    try {
      const first = await runtime.useCases.createCanonicalComic.execute({
        title: "Key Order Comic",
        description: "Same meaning",
        authorName: "Same Author",
        originHint: "remote",
        idempotencyKey: "key-order",
      });
      const second = await runtime.useCases.createCanonicalComic.execute({
        authorName: "Same Author",
        idempotencyKey: "key-order",
        originHint: "remote",
        description: "Same meaning",
        title: "Key Order Comic",
      });

      expect(first.ok).toBe(true);
      expect(second.ok).toBe(true);
      expect(await countComics(runtime)).toBe(1);
      if (first.ok && second.ok) {
        expect(second.value).toEqual(first.value);
      }
    } finally {
      runtime.close();
    }
  });

  it("normalizes title whitespace before hashing idempotent input", async () => {
    const runtime = await createTestRuntime();

    try {
      const first = await runtime.useCases.createCanonicalComic.execute({
        title: "Whitespace   Comic",
        idempotencyKey: "title-whitespace",
      });
      const second = await runtime.useCases.createCanonicalComic.execute({
        title: "  Whitespace Comic  ",
        idempotencyKey: "title-whitespace",
      });

      expect(first.ok).toBe(true);
      expect(second.ok).toBe(true);
      expect(await countComics(runtime)).toBe(1);
      if (first.ok && second.ok) {
        expect(second.value).toEqual(first.value);
      }
    } finally {
      runtime.close();
    }
  });

  it("returns IDEMPOTENCY_CONFLICT without mutation for the same key and different canonical input", async () => {
    const runtime = await createTestRuntime();

    try {
      const first = await runtime.useCases.createCanonicalComic.execute({
        title: "Conflict Comic",
        description: "v1",
        idempotencyKey: "conflict-key",
      });
      const second = await runtime.useCases.createCanonicalComic.execute({
        title: "Conflict Comic",
        description: "v2",
        idempotencyKey: "conflict-key",
      });

      expect(first.ok).toBe(true);
      expect(second.ok).toBe(false);
      if (!second.ok) {
        expect(second.error.code).toBe("IDEMPOTENCY_CONFLICT");
      }
      expect(await countComics(runtime)).toBe(1);
    } finally {
      runtime.close();
    }
  });

  it("fails closed for stale in_progress idempotency rows without replaying or mutating", async () => {
    const runtime = await createTestRuntime();

    try {
      await sql`
        INSERT INTO operation_idempotency (
          operation_name,
          idempotency_key,
          input_hash,
          status,
          result_json,
          created_at,
          updated_at
        )
        VALUES (
          'CreateCanonicalComic',
          'stale-key',
          'hash-stale',
          'in_progress',
          NULL,
          '2026-01-01T00:00:00.000Z',
          '2026-01-01T00:00:00.000Z'
        )
      `.execute(runtime.db);

      const result = await runtime.useCases.createCanonicalComic.execute({
        title: "Stale Comic",
        idempotencyKey: "stale-key",
      });

      expect(result.ok).toBe(false);
      expect(await countComics(runtime)).toBe(0);
    } finally {
      runtime.close();
    }
  });

  it("rolls back partial writes when title creation fails inside the transaction", async () => {
    const runtime = await createTestRuntime();

    try {
      const failingUseCase = new CreateCanonicalComic({
        clock: {
          now: () => new Date(),
        },
        idGenerator: {
          create: () => randomUUID(),
        },
        transaction: {
          runInTransaction: runtime.useCases.createCanonicalComic["dependencies"].transaction.runInTransaction,
        },
        repositories: {
          ...runtime.repositories,
          comicTitles: {
            ...runtime.repositories.comicTitles,
            addTitle: async () =>
              err(
                createCoreError({
                  code: "INTERNAL_ERROR",
                  message: "Injected title write failure.",
                }),
              ),
          },
        },
      });

      const result = await failingUseCase.execute({
        title: "Rollback Comic",
        idempotencyKey: "rollback-key",
      });

      expect(result.ok).toBe(false);

      const createdComics = await runtime.repositories.comics.listByNormalizedTitle("rollback comic" as never);
      expect(createdComics.ok).toBe(true);
      if (createdComics.ok) {
        expect(createdComics.value).toEqual([]);
      }

      expect(await readIdempotencyRows(runtime)).toEqual([]);
    } finally {
      runtime.close();
    }
  });
});
