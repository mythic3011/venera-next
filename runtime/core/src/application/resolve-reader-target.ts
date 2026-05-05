import {
  parseDiagnosticsEventId,
  type ChapterId,
  type ChapterSourceLinkId,
  type PageId,
  type SourceLinkId,
} from "../domain/identifiers.js";
import type {
  ReaderOpenTarget,
  ResolveReaderTargetInput,
} from "../domain/reader.js";
import type { CoreUseCaseDependencies } from "../ports/use-case-dependencies.js";
import { isErr, ok, type Result } from "../shared/result.js";
import { fail, unexpectedFailure, withOptional } from "./helpers.js";

function compareChapters(left: { chapterNumber: number; createdAt: Date }, right: { chapterNumber: number; createdAt: Date }): number {
  if (left.chapterNumber !== right.chapterNumber) {
    return left.chapterNumber - right.chapterNumber;
  }

  return left.createdAt.getTime() - right.createdAt.getTime();
}

export class ResolveReaderTarget {
  constructor(private readonly dependencies: CoreUseCaseDependencies) {}

  async execute(
    input: ResolveReaderTargetInput,
  ): Promise<Result<ReaderOpenTarget>> {
    try {
      const comic = await this.dependencies.repositories.comics.getById(input.comicId);
      if (isErr(comic)) {
        return comic;
      }

      if (comic.value === null) {
        return fail("NOT_FOUND", "Comic not found.");
      }

      const resolvedChapter = await this.resolveChapter(input);
      if (isErr(resolvedChapter)) {
        return resolvedChapter;
      }

      const sourceContext = await this.resolveSourceContext(resolvedChapter.value.chapterId);
      if (isErr(sourceContext)) {
        return sourceContext;
      }

      return ok(withOptional(withOptional(withOptional({
        comicId: input.comicId,
        chapterId: resolvedChapter.value.chapterId,
        pageIndex: resolvedChapter.value.pageIndex,
        sourceKind: sourceContext.value.sourceKind,
        resolutionReason: resolvedChapter.value.reason,
      }, "pageId", resolvedChapter.value.pageId), "sourceLinkId", sourceContext.value.sourceLinkId), "chapterSourceLinkId", sourceContext.value.chapterSourceLinkId));
    } catch (cause) {
      return unexpectedFailure("ResolveReaderTarget failed.", cause);
    }
  }

  private async resolveChapter(
    input: ResolveReaderTargetInput,
  ): Promise<Result<{ chapterId: ChapterId; pageIndex: number; pageId?: PageId; reason: "requested_chapter" | "saved_session" | "first_canonical_chapter" }>> {
    if (input.chapterId !== undefined) {
      const chapter = await this.dependencies.repositories.chapters.getById(input.chapterId);
      if (isErr(chapter)) {
        return chapter;
      }

      if (chapter.value === null || chapter.value.comicId !== input.comicId) {
        return this.emitUnresolvedTarget(input, "requested_chapter_missing");
      }

      return ok({
        chapterId: chapter.value.id,
        pageIndex: input.pageIndex ?? 0,
        reason: "requested_chapter",
      });
    }

    const savedSession = await this.dependencies.repositories.readerSessions.getByComic(
      input.comicId,
    );
    if (isErr(savedSession)) {
      return savedSession;
    }

    if (savedSession.value !== null) {
      const chapter = await this.dependencies.repositories.chapters.getById(
        savedSession.value.chapterId,
      );
      if (!isErr(chapter) && chapter.value !== null && chapter.value.comicId === input.comicId) {
        return ok(withOptional({
          chapterId: savedSession.value.chapterId,
          pageIndex: input.pageIndex ?? savedSession.value.pageIndex,
          reason: "saved_session",
        }, "pageId", savedSession.value.pageId));
      }
    }

    const chapters = await this.dependencies.repositories.chapters.listByComic(input.comicId);
    if (isErr(chapters)) {
      return chapters;
    }

    const firstChapter = [...chapters.value].sort(compareChapters)[0];
    if (firstChapter === undefined) {
      return this.emitUnresolvedTarget(input, "missing_local_chapter_id");
    }

    return ok({
      chapterId: firstChapter.id,
      pageIndex: input.pageIndex ?? 0,
      reason: "first_canonical_chapter",
    });
  }

  private async resolveSourceContext(
    chapterId: ChapterId,
  ): Promise<Result<{
    sourceKind: "local" | "remote";
    sourceLinkId?: SourceLinkId;
    chapterSourceLinkId?: ChapterSourceLinkId;
  }>> {
    const chapterLinks = await this.dependencies.repositories.chapterSourceLinks.listByChapter(
      chapterId,
    );
    if (isErr(chapterLinks)) {
      return chapterLinks;
    }

    const activeLink = chapterLinks.value.find((link) => link.linkStatus === "active");
    if (activeLink === undefined) {
      return ok({
        sourceKind: "local",
      });
    }

    return ok({
      sourceKind: "remote",
      sourceLinkId: activeLink.sourceLinkId,
      chapterSourceLinkId: activeLink.id,
    });
  }

  private async emitUnresolvedTarget(
    input: ResolveReaderTargetInput,
    reason: string,
  ): Promise<Result<never>> {
    const eventId = parseDiagnosticsEventId(this.dependencies.idGenerator.create());
    if (!isErr(eventId)) {
      await this.dependencies.repositories.diagnosticsEvents.record(withOptional({
        id: eventId.value,
        timestamp: this.dependencies.clock.now(),
        level: "warn",
        channel: "reader.route",
        eventName: "reader.route.unresolved_target",
        boundary: "reader.open",
        action: "rejected",
        authority: "canonical_db",
        comicId: input.comicId,
        payload: {
          comicId: input.comicId,
          chapterId: input.chapterId ?? null,
          sourceKind: "local",
          reason,
          action: "rejected",
        },
      }, "correlationId", input.correlationId));
    }

    return fail(
      "READER_UNRESOLVED_LOCAL_TARGET",
      "Unable to resolve a canonical reader target.",
      {
        reason,
      },
    );
  }
}
