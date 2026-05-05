import type { ReaderSessionPersistResult, UpdateReaderPositionInput } from "../domain/reader.js";
import type { CoreUseCaseDependencies } from "../ports/use-case-dependencies.js";
import { isErr, type Result } from "../shared/result.js";
import { fail, unexpectedFailure } from "./helpers.js";

export class UpdateReaderPosition {
  constructor(private readonly dependencies: CoreUseCaseDependencies) {}

  async execute(
    input: UpdateReaderPositionInput,
  ): Promise<Result<ReaderSessionPersistResult>> {
    try {
      const comic = await this.dependencies.repositories.comics.getById(input.comicId);
      if (isErr(comic)) {
        return comic;
      }

      if (comic.value === null) {
        return fail("NOT_FOUND", "Comic not found.");
      }

      const chapter = await this.dependencies.repositories.chapters.getById(input.chapterId);
      if (isErr(chapter)) {
        return chapter;
      }

      if (chapter.value === null || chapter.value.comicId !== input.comicId) {
        return fail(
          "READER_INVALID_POSITION",
          "Chapter does not belong to the requested comic.",
        );
      }

      const pages = await this.dependencies.repositories.pages.listByChapter(input.chapterId);
      if (isErr(pages)) {
        return pages;
      }

      if (input.pageIndex < 0 || input.pageIndex >= pages.value.length) {
        return fail(
          "READER_INVALID_POSITION",
          "Page index is outside the chapter page range.",
          {
            pageIndex: input.pageIndex,
            pageCount: pages.value.length,
          },
        );
      }

      if (input.pageId !== undefined) {
        const page = await this.dependencies.repositories.pages.getById(input.pageId);
        if (isErr(page)) {
          return page;
        }

        if (page.value === null || page.value.chapterId !== input.chapterId) {
          return fail(
            "READER_INVALID_POSITION",
            "Page does not belong to the requested chapter.",
          );
        }
      }

      const existing = await this.dependencies.repositories.readerSessions.getByComic(
        input.comicId,
      );
      if (isErr(existing)) {
        return existing;
      }

      if (
        existing.value !== null &&
        existing.value.chapterId === input.chapterId &&
        existing.value.pageId === input.pageId &&
        existing.value.pageIndex === input.pageIndex &&
        existing.value.readerMode === input.readerMode &&
        existing.value.sourceLinkId === input.sourceLinkId &&
        existing.value.chapterSourceLinkId === input.chapterSourceLinkId
      ) {
        return {
          ok: true,
          value: {
            session: existing.value,
            status: "skipped_unchanged",
          },
        };
      }

      return this.dependencies.repositories.readerSessions.upsertPosition(input);
    } catch (cause) {
      return unexpectedFailure("UpdateReaderPosition failed.", cause);
    }
  }
}
