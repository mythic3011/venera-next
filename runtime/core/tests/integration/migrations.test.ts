import { describe, expect, it } from "vitest";
import { sql } from "kysely";

import { openRuntimeDatabase } from "../../src/db/database.js";
import { migrateCoreDatabase } from "../../src/db/migrations.js";
import { createTestRuntime } from "../support/test-runtime.js";

describe("core database migrations and seed", () => {
  it("creates the required tables, passes foreign key checks, and seeds local source", async () => {
    const runtime = await createTestRuntime();

    try {
      const tables = await sql<{ name: string }>`
        SELECT name
        FROM sqlite_master
        WHERE type = 'table'
        ORDER BY name
      `.execute(runtime.db);

      expect(tables.rows.map((row) => row.name)).toEqual(
        expect.arrayContaining([
          "chapters",
          "comic_metadata",
          "comic_titles",
          "comics",
          "diagnostics_events",
          "operation_idempotency",
          "page_order_items",
          "page_orders",
          "pages",
          "reader_sessions",
          "source_links",
          "source_platforms",
          "storage_backends",
          "storage_objects",
          "storage_placements",
        ]),
      );

      const foreignKeyCheck = await sql`
        PRAGMA foreign_key_check
      `.execute(runtime.db);
      expect(foreignKeyCheck.rows).toEqual([]);

      const localSource = await runtime.repositories.sourcePlatforms.getByKey("local");
      expect(localSource.ok).toBe(true);
      if (localSource.ok) {
        expect(localSource.value?.canonicalKey).toBe("local");
        expect(localSource.value?.kind).toBe("local");
      }
    } finally {
      runtime.close();
    }
  });

  it("defines comics.normalized_title as a non-unique indexed lookup", async () => {
    const handle = openRuntimeDatabase({
      databasePath: ":memory:",
    });

    try {
      await migrateCoreDatabase(handle.db);

      const now = new Date().toISOString();

      await sql`
        INSERT INTO comics (id, normalized_title, origin_hint, created_at, updated_at)
        VALUES ('11111111-1111-4111-8111-111111111111', 'same-title', 'local', ${now}, ${now})
      `.execute(handle.db);

      await expect(
        sql`
          INSERT INTO comics (id, normalized_title, origin_hint, created_at, updated_at)
          VALUES ('22222222-2222-4222-8222-222222222222', 'same-title', 'remote', ${now}, ${now})
        `.execute(handle.db),
      ).resolves.toBeDefined();

      const indexes = await sql<{ name: string; unique: number }>`
        PRAGMA index_list('comics')
      `.execute(handle.db);

      expect(indexes.rows).toEqual(
        expect.arrayContaining([
          expect.objectContaining({
            name: "idx_comics_normalized_title",
            unique: 0,
          }),
        ]),
      );
    } finally {
      handle.close();
    }
  });
});
