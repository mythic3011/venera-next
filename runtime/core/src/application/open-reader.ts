import type {
  OpenReaderInput,
  OpenReaderResult,
  ReaderPageEntry,
} from "../domain/reader.js";
import type { CoreUseCaseDependencies } from "../ports/use-case-dependencies.js";
import { isErr, ok, type Result } from "../shared/result.js";
import { fail, unexpectedFailure } from "./helpers.js";
import { ResolveReaderTarget } from "./resolve-reader-target.js";

export class OpenReader {
  private readonly resolveReaderTarget: ResolveReaderTarget;

  constructor(private readonly dependencies: CoreUseCaseDependencies) {
    this.resolveReaderTarget = new ResolveReaderTarget(dependencies);
  }

  async execute(input: OpenReaderInput): Promise<Result<OpenReaderResult>> {
    try {
      const target = await this.resolveReaderTarget.execute(input);
      if (isErr(target)) {
        return target;
      }

      const chapter = await this.dependencies.repositories.chapters.getById(target.value.chapterId);
      if (isErr(chapter)) {
        return chapter;
      }

      if (chapter.value === null) {
        return fail(
          "READER_UNRESOLVED_LOCAL_TARGET",
          "Resolved chapter no longer exists.",
        );
      }

      const pagesResult = await this.dependencies.repositories.pages.listByChapter(target.value.chapterId);
      if (isErr(pagesResult)) {
        return pagesResult;
      }

      const activeOrderResult = await this.dependencies.repositories.pageOrders.getActiveOrder(
        target.value.chapterId,
      );
      if (isErr(activeOrderResult)) {
        return activeOrderResult;
      }

      const activeOrder = activeOrderResult.value ?? {
        order: {
          id: `synthetic:${target.value.chapterId}` as never,
          chapterId: target.value.chapterId,
          orderKey: "source",
          orderType: "source",
          isActive: true,
          pageCount: pagesResult.value.length,
          createdAt: this.dependencies.clock.now(),
          updatedAt: this.dependencies.clock.now(),
        },
        items: pagesResult.value.map((page) => ({
          id: `synthetic:${page.id}` as never,
          pageOrderId: `synthetic:${target.value.chapterId}` as never,
          pageId: page.id,
          sortIndex: page.pageIndex,
          createdAt: page.createdAt,
        })),
      };

      const pagesById = new Map(pagesResult.value.map((page) => [page.id, page]));
      const orderedPages: ReaderPageEntry[] = activeOrder.items
        .map((item) => {
          const page = pagesById.get(item.pageId);
          if (page === undefined) {
            return null;
          }

          return {
            page,
            sortIndex: item.sortIndex,
          };
        })
        .filter((entry): entry is ReaderPageEntry => entry !== null)
        .sort((left, right) => left.sortIndex - right.sortIndex);

      if (orderedPages.length === 0) {
        return fail("NOT_FOUND", "No pages exist for the resolved chapter.");
      }

      if (target.value.pageIndex < 0 || target.value.pageIndex >= orderedPages.length) {
        return fail(
          "READER_INVALID_POSITION",
          "Reader page index is outside the available page range.",
          {
            pageIndex: target.value.pageIndex,
            pageCount: orderedPages.length,
          },
        );
      }

      return ok({
        target: target.value,
        chapter: chapter.value,
        activeOrder,
        pages: orderedPages,
      });
    } catch (cause) {
      return unexpectedFailure("OpenReader failed.", cause);
    }
  }
}
