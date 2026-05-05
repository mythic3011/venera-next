import { describe, expect, it } from "vitest";
import { sql } from "kysely";

import { createTestRuntime, insertComicFixture, nextId } from "../support/test-runtime.js";

describe("reader use cases", () => {
  it("ResolveReaderTarget owns fallback order: requested chapter, saved session, then first canonical chapter", async () => {
    const runtime = await createTestRuntime();

    try {
      const fixture = await insertComicFixture(runtime, {
        chapterIds: [nextId(), nextId()],
      });
      const now = new Date().toISOString();

      const savedSessionId = nextId();
      await sql`
        INSERT INTO reader_sessions (
          id,
          comic_id,
          chapter_id,
          page_id,
          page_index,
          source_link_id,
          chapter_source_link_id,
          reader_mode,
          created_at,
          updated_at
        )
        VALUES (
          ${savedSessionId},
          ${fixture.comicId},
          ${fixture.chapterIds[1]},
          NULL,
          1,
          NULL,
          NULL,
          'continuous',
          ${now},
          ${now}
        )
      `.execute(runtime.db);

      const requested = await runtime.useCases.resolveReaderTarget.execute({
        comicId: fixture.comicId as never,
        chapterId: fixture.chapterIds[0] as never,
      });
      expect(requested.ok && requested.value.resolutionReason).toBe("requested_chapter");

      const saved = await runtime.useCases.resolveReaderTarget.execute({
        comicId: fixture.comicId as never,
      });
      expect(saved.ok && saved.value.chapterId).toBe(fixture.chapterIds[1]);
      expect(saved.ok && saved.value.resolutionReason).toBe("saved_session");

      await runtime.repositories.readerSessions.clear(fixture.comicId as never);
      const fallback = await runtime.useCases.resolveReaderTarget.execute({
        comicId: fixture.comicId as never,
      });
      expect(fallback.ok && fallback.value.chapterId).toBe(fixture.chapterIds[0]);
      expect(fallback.ok && fallback.value.resolutionReason).toBe("first_canonical_chapter");
    } finally {
      runtime.close();
    }
  });

  it("OpenReader fails closed when no canonical chapter exists", async () => {
    const runtime = await createTestRuntime();

    try {
      const now = new Date().toISOString();
      const comicId = nextId();
      await sql`
        INSERT INTO comics (id, normalized_title, origin_hint, created_at, updated_at)
        VALUES (${comicId}, 'empty-comic', 'local', ${now}, ${now})
      `.execute(runtime.db);

      const result = await runtime.useCases.openReader.execute({
        comicId: comicId as never,
      });

      expect(result.ok).toBe(false);
      if (!result.ok) {
        expect(result.error.code).toBe("READER_UNRESOLVED_LOCAL_TARGET");
      }
    } finally {
      runtime.close();
    }
  });

  it("UpdateReaderPosition skips unchanged writes", async () => {
    const runtime = await createTestRuntime();

    try {
      const fixture = await insertComicFixture(runtime);
      const firstWrite = await runtime.useCases.updateReaderPosition.execute({
        comicId: fixture.comicId as never,
        chapterId: fixture.chapterIds[0] as never,
        pageId: fixture.pageIds[1] as never,
        pageIndex: 1,
        readerMode: "continuous",
      });
      expect(firstWrite.ok && firstWrite.value.status).toBe("written");

      const secondWrite = await runtime.useCases.updateReaderPosition.execute({
        comicId: fixture.comicId as never,
        chapterId: fixture.chapterIds[0] as never,
        pageId: fixture.pageIds[1] as never,
        pageIndex: 1,
        readerMode: "continuous",
      });
      expect(secondWrite.ok && secondWrite.value.status).toBe("skipped_unchanged");
    } finally {
      runtime.close();
    }
  });
});
