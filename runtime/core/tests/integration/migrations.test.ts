import { describe, expect, it } from "vitest";
import { sql } from "kysely";

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
});
