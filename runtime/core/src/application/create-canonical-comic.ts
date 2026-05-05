import {
  buildPrimaryComicTitle,
  parseDisplayTitle,
  parseNormalizedTitle,
  type CreateCanonicalComicInput,
  type CreatedCanonicalComic,
} from "../domain/comic.js";
import {
  parseComicId,
  parseComicTitleId,
} from "../domain/identifiers.js";
import type { CoreUseCaseDependencies } from "../ports/use-case-dependencies.js";
import { isErr, ok, type Result } from "../shared/result.js";
import { fail, unexpectedFailure, withOptional } from "./helpers.js";

export class CreateCanonicalComic {
  constructor(private readonly dependencies: CoreUseCaseDependencies) {}

  async execute(
    input: CreateCanonicalComicInput,
  ): Promise<Result<CreatedCanonicalComic>> {
    try {
      const title = parseDisplayTitle(input.title);
      if (isErr(title)) {
        return title;
      }

      const normalizedTitle = parseNormalizedTitle(input.title);
      if (isErr(normalizedTitle)) {
        return normalizedTitle;
      }

      const existing = await this.dependencies.repositories.comics.getByNormalizedTitle(
        normalizedTitle.value,
      );
      if (isErr(existing)) {
        return existing;
      }

      if (existing.value !== null) {
        return fail(
          "DUPLICATE",
          "A canonical comic with the same normalized title already exists.",
          {
            normalizedTitle: normalizedTitle.value,
          },
        );
      }

      return this.dependencies.transaction.runInTransaction(async () => {
        const now = this.dependencies.clock.now();
        const comicId = parseComicId(this.dependencies.idGenerator.create());
        if (isErr(comicId)) {
          return comicId;
        }

        const comicResult = await this.dependencies.repositories.comics.create({
          id: comicId.value,
          normalizedTitle: normalizedTitle.value,
          originHint: input.originHint ?? "unknown",
          createdAt: now,
          updatedAt: now,
        });
        if (isErr(comicResult)) {
          return comicResult;
        }

        const metadataInput = withOptional(
          withOptional(
            {
              comicId: comicId.value,
              title: title.value,
              createdAt: now,
              updatedAt: now,
            },
            "description",
            input.description,
          ),
          "authorName",
          input.authorName,
        );

        const metadataResult = await this.dependencies.repositories.comicMetadata.create(
          metadataInput,
        );
        if (isErr(metadataResult)) {
          return metadataResult;
        }

        const titleId = parseComicTitleId(this.dependencies.idGenerator.create());
        if (isErr(titleId)) {
          return titleId;
        }

        const primaryTitle = buildPrimaryComicTitle({
          id: titleId.value,
          comicId: comicId.value,
          title: title.value,
          normalizedTitle: normalizedTitle.value,
          createdAt: now,
        });
        if (isErr(primaryTitle)) {
          return primaryTitle;
        }

        const titleResult = await this.dependencies.repositories.comicTitles.addTitle(
          primaryTitle.value,
        );
        if (isErr(titleResult)) {
          return titleResult;
        }

        return ok({
          comic: comicResult.value,
          metadata: metadataResult.value,
          primaryTitle: titleResult.value,
        });
      });
    } catch (cause) {
      return unexpectedFailure("CreateCanonicalComic failed.", cause);
    }
  }
}
