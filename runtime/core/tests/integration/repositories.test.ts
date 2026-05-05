import { describe, expect, it } from "vitest";

import { createTestRuntime, insertComicFixture } from "../support/test-runtime.js";

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
});
