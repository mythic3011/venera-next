import { randomUUID } from "node:crypto";

import { describe, expect, it } from "vitest";

import { CreateCanonicalComic } from "../../src/application/create-canonical-comic.js";
import { createCoreError } from "../../src/shared/errors.js";
import { err } from "../../src/shared/result.js";
import { createTestRuntime } from "../support/test-runtime.js";

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
      });

      expect(result.ok).toBe(false);

      const createdComic = await runtime.repositories.comics.getByNormalizedTitle("rollback comic" as never);
      expect(createdComic.ok).toBe(true);
      if (createdComic.ok) {
        expect(createdComic.value).toBeNull();
      }
    } finally {
      runtime.close();
    }
  });
});
