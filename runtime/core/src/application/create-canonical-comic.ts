import { createHash } from "node:crypto";

import {
  buildPrimaryComicTitle,
  COMIC_ORIGIN_HINTS,
  COMIC_TITLE_KINDS,
  parseDisplayTitle,
  parseNormalizedTitle,
  type ComicOriginHint,
  type ComicTitle,
  type CreateCanonicalComicInput,
  type CreatedCanonicalComic,
} from "../domain/comic.js";
import {
  CREATE_CANONICAL_COMIC_OPERATION_NAME,
  CREATED_CANONICAL_COMIC_RESULT_TYPE,
  IDEMPOTENCY_RESULT_SCHEMA_VERSION,
  parseIdempotencyKey,
  parseInputHash,
} from "../domain/idempotency.js";
import {
  parseComicId,
  parseComicTitleId,
  parsePageId,
  parseSourceLinkId,
  parseSourcePlatformId,
  parseStorageObjectId,
} from "../domain/identifiers.js";
import type { CoreUseCaseDependencies } from "../ports/use-case-dependencies.js";
import type { JsonObject, JsonValue } from "../shared/json.js";
import { isErr, ok, type Result } from "../shared/result.js";
import { normalizeWhitespace } from "../shared/validation.js";
import { fail, unexpectedFailure, withOptional } from "./helpers.js";

interface CanonicalCreateCanonicalComicInput {
  readonly title: string;
  readonly normalizedTitle: string;
  readonly description?: string;
  readonly authorName?: string;
  readonly originHint: ComicOriginHint;
}

function normalizeOptionalText(value: string | undefined): string | undefined {
  if (value === undefined) {
    return undefined;
  }

  const normalized = normalizeWhitespace(value);
  return normalized.length === 0 ? undefined : normalized;
}

function canonicalizeCreateCanonicalComicInput(
  input: CreateCanonicalComicInput,
  normalizedTitle: string,
): CanonicalCreateCanonicalComicInput {
  return withOptional(
    withOptional(
      {
        title: normalizeWhitespace(input.title),
        normalizedTitle,
        originHint: input.originHint ?? "unknown",
      },
      "description",
      normalizeOptionalText(input.description),
    ),
    "authorName",
    normalizeOptionalText(input.authorName),
  );
}

function stableJsonValue(value: unknown): unknown {
  if (Array.isArray(value)) {
    return value.map((entry) => stableJsonValue(entry));
  }

  if (value !== null && typeof value === "object") {
    return Object.fromEntries(
      Object.entries(value)
        .filter(([, entryValue]) => entryValue !== undefined)
        .sort(([left], [right]) => left.localeCompare(right))
        .map(([key, entryValue]) => [key, stableJsonValue(entryValue)]),
    );
  }

  return value;
}

function hashCanonicalInput(input: CanonicalCreateCanonicalComicInput): string {
  return createHash("sha256")
    .update(JSON.stringify(stableJsonValue(input)))
    .digest("hex");
}

function expectExactKeys(
  value: JsonObject,
  allowedKeys: readonly string[],
  path: string,
): Result<void> {
  const unexpectedKeys = Object.keys(value).filter((key) => !allowedKeys.includes(key));
  if (unexpectedKeys.length > 0) {
    return fail(
      "INTERNAL_ERROR",
      "Stored idempotency replay payload is invalid.",
      {
        path,
        reason: "unexpected_keys",
        unexpectedKeys: unexpectedKeys.join(","),
      },
    );
  }

  return ok(undefined);
}

function expectObject(
  value: JsonObject,
  key: string,
  path: string,
): Result<JsonObject> {
  const child = value[key];
  if (child === undefined || child === null || Array.isArray(child) || typeof child !== "object") {
    return fail(
      "INTERNAL_ERROR",
      "Stored idempotency replay payload is invalid.",
      {
        path: `${path}.${key}`,
        reason: "missing_object",
      },
    );
  }

  return ok(child as JsonObject);
}

function expectString(
  value: JsonObject,
  key: string,
  path: string,
): Result<string> {
  const child = value[key];
  if (typeof child !== "string") {
    return fail(
      "INTERNAL_ERROR",
      "Stored idempotency replay payload is invalid.",
      {
        path: `${path}.${key}`,
        reason: "missing_string",
      },
    );
  }

  return ok(child);
}

function expectOptionalString(
  value: JsonObject,
  key: string,
  path: string,
): Result<string | undefined> {
  const child = value[key];
  if (child === undefined) {
    return ok(undefined);
  }

  if (typeof child !== "string") {
    return fail(
      "INTERNAL_ERROR",
      "Stored idempotency replay payload is invalid.",
      {
        path: `${path}.${key}`,
        reason: "invalid_optional_string",
      },
    );
  }

  return ok(child);
}

function expectOptionalObject(
  value: JsonObject,
  key: string,
  path: string,
): Result<JsonObject | undefined> {
  const child = value[key];
  if (child === undefined) {
    return ok(undefined);
  }

  if (child === null || Array.isArray(child) || typeof child !== "object") {
    return fail(
      "INTERNAL_ERROR",
      "Stored idempotency replay payload is invalid.",
      {
        path: `${path}.${key}`,
        reason: "invalid_optional_object",
      },
    );
  }

  return ok(child as JsonObject);
}

function readDate(
  value: JsonObject,
  key: string,
  path: string,
): Result<Date> {
  const raw = expectString(value, key, path);
  if (isErr(raw)) {
    return raw;
  }

  const date = new Date(raw.value);
  if (Number.isNaN(date.getTime())) {
    return fail(
      "INTERNAL_ERROR",
      "Stored idempotency replay payload is invalid.",
      {
        path: `${path}.${key}`,
        reason: "invalid_date",
      },
    );
  }

  return ok(date);
}

function serializeCreatedCanonicalComicReplay(
  value: CreatedCanonicalComic,
): JsonObject {
  const metadata: Record<string, JsonValue | undefined> = {
    comicId: value.metadata.comicId,
    title: value.metadata.title,
    createdAt: value.metadata.createdAt.toISOString(),
    updatedAt: value.metadata.updatedAt.toISOString(),
  };
  if (value.metadata.description !== undefined) {
    metadata.description = value.metadata.description;
  }
  if (value.metadata.coverPageId !== undefined) {
    metadata.coverPageId = value.metadata.coverPageId;
  }
  if (value.metadata.coverStorageObjectId !== undefined) {
    metadata.coverStorageObjectId = value.metadata.coverStorageObjectId;
  }
  if (value.metadata.authorName !== undefined) {
    metadata.authorName = value.metadata.authorName;
  }
  if (value.metadata.metadata !== undefined) {
    metadata.metadata = value.metadata.metadata;
  }

  const primaryTitle: Record<string, JsonValue | undefined> = {
    id: value.primaryTitle.id,
    comicId: value.primaryTitle.comicId,
    title: value.primaryTitle.title,
    normalizedTitle: value.primaryTitle.normalizedTitle,
    titleKind: value.primaryTitle.titleKind,
    createdAt: value.primaryTitle.createdAt.toISOString(),
  };
  if (value.primaryTitle.locale !== undefined) {
    primaryTitle.locale = value.primaryTitle.locale;
  }
  if (value.primaryTitle.sourcePlatformId !== undefined) {
    primaryTitle.sourcePlatformId = value.primaryTitle.sourcePlatformId;
  }
  if (value.primaryTitle.sourceLinkId !== undefined) {
    primaryTitle.sourceLinkId = value.primaryTitle.sourceLinkId;
  }

  return {
    comic: {
      id: value.comic.id,
      normalizedTitle: value.comic.normalizedTitle,
      originHint: value.comic.originHint,
      createdAt: value.comic.createdAt.toISOString(),
      updatedAt: value.comic.updatedAt.toISOString(),
    },
    metadata,
    primaryTitle,
  } as JsonObject;
}

function mapReplayToCreatedCanonicalComic(
  replay: JsonObject,
): Result<CreatedCanonicalComic> {
  const rootKeyCheck = expectExactKeys(
    replay,
    ["comic", "metadata", "primaryTitle"],
    "createdCanonicalComic",
  );
  if (isErr(rootKeyCheck)) {
    return rootKeyCheck;
  }

  const comicObject = expectObject(replay, "comic", "createdCanonicalComic");
  if (isErr(comicObject)) {
    return comicObject;
  }
  const metadataObject = expectObject(replay, "metadata", "createdCanonicalComic");
  if (isErr(metadataObject)) {
    return metadataObject;
  }
  const primaryTitleObject = expectObject(replay, "primaryTitle", "createdCanonicalComic");
  if (isErr(primaryTitleObject)) {
    return primaryTitleObject;
  }

  const comicKeyCheck = expectExactKeys(
    comicObject.value,
    ["id", "normalizedTitle", "originHint", "createdAt", "updatedAt"],
    "createdCanonicalComic.comic",
  );
  if (isErr(comicKeyCheck)) {
    return comicKeyCheck;
  }
  const metadataKeyCheck = expectExactKeys(
    metadataObject.value,
    [
      "comicId",
      "title",
      "description",
      "coverPageId",
      "coverStorageObjectId",
      "authorName",
      "metadata",
      "createdAt",
      "updatedAt",
    ],
    "createdCanonicalComic.metadata",
  );
  if (isErr(metadataKeyCheck)) {
    return metadataKeyCheck;
  }
  const primaryTitleKeyCheck = expectExactKeys(
    primaryTitleObject.value,
    [
      "id",
      "comicId",
      "title",
      "normalizedTitle",
      "locale",
      "sourcePlatformId",
      "sourceLinkId",
      "titleKind",
      "createdAt",
    ],
    "createdCanonicalComic.primaryTitle",
  );
  if (isErr(primaryTitleKeyCheck)) {
    return primaryTitleKeyCheck;
  }

  const comicIdRaw = expectString(comicObject.value, "id", "createdCanonicalComic.comic");
  if (isErr(comicIdRaw)) {
    return comicIdRaw;
  }
  const comicId = parseComicId(comicIdRaw.value);
  if (isErr(comicId)) {
    return comicId;
  }
  const normalizedTitleRaw = expectString(
    comicObject.value,
    "normalizedTitle",
    "createdCanonicalComic.comic",
  );
  if (isErr(normalizedTitleRaw)) {
    return normalizedTitleRaw;
  }
  const normalizedTitle = parseNormalizedTitle(normalizedTitleRaw.value);
  if (isErr(normalizedTitle)) {
    return normalizedTitle;
  }
  const originHint = expectString(comicObject.value, "originHint", "createdCanonicalComic.comic");
  if (isErr(originHint)) {
    return originHint;
  }
  if (!COMIC_ORIGIN_HINTS.includes(originHint.value as ComicOriginHint)) {
    return fail(
      "INTERNAL_ERROR",
      "Stored idempotency replay payload is invalid.",
      {
        path: "createdCanonicalComic.comic.originHint",
        reason: "invalid_enum",
      },
    );
  }
  const metadataComicIdRaw = expectString(
    metadataObject.value,
    "comicId",
    "createdCanonicalComic.metadata",
  );
  if (isErr(metadataComicIdRaw)) {
    return metadataComicIdRaw;
  }
  const metadataComicId = parseComicId(metadataComicIdRaw.value);
  if (isErr(metadataComicId)) {
    return metadataComicId;
  }
  const metadataTitleRaw = expectString(
    metadataObject.value,
    "title",
    "createdCanonicalComic.metadata",
  );
  if (isErr(metadataTitleRaw)) {
    return metadataTitleRaw;
  }
  const metadataTitle = parseDisplayTitle(metadataTitleRaw.value);
  if (isErr(metadataTitle)) {
    return metadataTitle;
  }
  const metadataDescription = expectOptionalString(
    metadataObject.value,
    "description",
    "createdCanonicalComic.metadata",
  );
  if (isErr(metadataDescription)) {
    return metadataDescription;
  }
  const metadataCoverPageIdRaw = expectOptionalString(
    metadataObject.value,
    "coverPageId",
    "createdCanonicalComic.metadata",
  );
  if (isErr(metadataCoverPageIdRaw)) {
    return metadataCoverPageIdRaw;
  }
  const metadataCoverPageId =
    metadataCoverPageIdRaw.value === undefined
      ? ok(undefined)
      : parsePageId(metadataCoverPageIdRaw.value);
  if (isErr(metadataCoverPageId)) {
    return metadataCoverPageId;
  }
  const metadataCoverStorageObjectIdRaw = expectOptionalString(
    metadataObject.value,
    "coverStorageObjectId",
    "createdCanonicalComic.metadata",
  );
  if (isErr(metadataCoverStorageObjectIdRaw)) {
    return metadataCoverStorageObjectIdRaw;
  }
  const metadataCoverStorageObjectId =
    metadataCoverStorageObjectIdRaw.value === undefined
      ? ok(undefined)
      : parseStorageObjectId(metadataCoverStorageObjectIdRaw.value);
  if (isErr(metadataCoverStorageObjectId)) {
    return metadataCoverStorageObjectId;
  }
  const metadataAuthorName = expectOptionalString(
    metadataObject.value,
    "authorName",
    "createdCanonicalComic.metadata",
  );
  if (isErr(metadataAuthorName)) {
    return metadataAuthorName;
  }
  const metadataPayload = expectOptionalObject(
    metadataObject.value,
    "metadata",
    "createdCanonicalComic.metadata",
  );
  if (isErr(metadataPayload)) {
    return metadataPayload;
  }
  const primaryTitleIdRaw = expectString(
    primaryTitleObject.value,
    "id",
    "createdCanonicalComic.primaryTitle",
  );
  if (isErr(primaryTitleIdRaw)) {
    return primaryTitleIdRaw;
  }
  const primaryTitleId = parseComicTitleId(primaryTitleIdRaw.value);
  if (isErr(primaryTitleId)) {
    return primaryTitleId;
  }
  const primaryTitleComicIdRaw = expectString(
    primaryTitleObject.value,
    "comicId",
    "createdCanonicalComic.primaryTitle",
  );
  if (isErr(primaryTitleComicIdRaw)) {
    return primaryTitleComicIdRaw;
  }
  const primaryTitleComicId = parseComicId(primaryTitleComicIdRaw.value);
  if (isErr(primaryTitleComicId)) {
    return primaryTitleComicId;
  }
  const primaryTitleTitleRaw = expectString(
    primaryTitleObject.value,
    "title",
    "createdCanonicalComic.primaryTitle",
  );
  if (isErr(primaryTitleTitleRaw)) {
    return primaryTitleTitleRaw;
  }
  const primaryTitleTitle = parseDisplayTitle(primaryTitleTitleRaw.value);
  if (isErr(primaryTitleTitle)) {
    return primaryTitleTitle;
  }
  const primaryTitleNormalizedTitleRaw = expectString(
    primaryTitleObject.value,
    "normalizedTitle",
    "createdCanonicalComic.primaryTitle",
  );
  if (isErr(primaryTitleNormalizedTitleRaw)) {
    return primaryTitleNormalizedTitleRaw;
  }
  const primaryTitleNormalizedTitle = parseNormalizedTitle(primaryTitleNormalizedTitleRaw.value);
  if (isErr(primaryTitleNormalizedTitle)) {
    return primaryTitleNormalizedTitle;
  }
  const primaryTitleLocale = expectOptionalString(
    primaryTitleObject.value,
    "locale",
    "createdCanonicalComic.primaryTitle",
  );
  if (isErr(primaryTitleLocale)) {
    return primaryTitleLocale;
  }
  const primaryTitleSourcePlatformIdRaw = expectOptionalString(
    primaryTitleObject.value,
    "sourcePlatformId",
    "createdCanonicalComic.primaryTitle",
  );
  if (isErr(primaryTitleSourcePlatformIdRaw)) {
    return primaryTitleSourcePlatformIdRaw;
  }
  const primaryTitleSourcePlatformId =
    primaryTitleSourcePlatformIdRaw.value === undefined
      ? ok(undefined)
      : parseSourcePlatformId(primaryTitleSourcePlatformIdRaw.value);
  if (isErr(primaryTitleSourcePlatformId)) {
    return primaryTitleSourcePlatformId;
  }
  const primaryTitleSourceLinkIdRaw = expectOptionalString(
    primaryTitleObject.value,
    "sourceLinkId",
    "createdCanonicalComic.primaryTitle",
  );
  if (isErr(primaryTitleSourceLinkIdRaw)) {
    return primaryTitleSourceLinkIdRaw;
  }
  const primaryTitleSourceLinkId =
    primaryTitleSourceLinkIdRaw.value === undefined
      ? ok(undefined)
      : parseSourceLinkId(primaryTitleSourceLinkIdRaw.value);
  if (isErr(primaryTitleSourceLinkId)) {
    return primaryTitleSourceLinkId;
  }
  const primaryTitleKind = expectString(
    primaryTitleObject.value,
    "titleKind",
    "createdCanonicalComic.primaryTitle",
  );
  if (isErr(primaryTitleKind)) {
    return primaryTitleKind;
  }
  if (!COMIC_TITLE_KINDS.includes(primaryTitleKind.value as ComicTitle["titleKind"])) {
    return fail(
      "INTERNAL_ERROR",
      "Stored idempotency replay payload is invalid.",
      {
        path: "createdCanonicalComic.primaryTitle.titleKind",
        reason: "invalid_enum",
      },
    );
  }

  const comicCreatedAt = readDate(comicObject.value, "createdAt", "createdCanonicalComic.comic");
  if (isErr(comicCreatedAt)) {
    return comicCreatedAt;
  }
  const comicUpdatedAt = readDate(comicObject.value, "updatedAt", "createdCanonicalComic.comic");
  if (isErr(comicUpdatedAt)) {
    return comicUpdatedAt;
  }
  const metadataCreatedAt = readDate(
    metadataObject.value,
    "createdAt",
    "createdCanonicalComic.metadata",
  );
  if (isErr(metadataCreatedAt)) {
    return metadataCreatedAt;
  }
  const metadataUpdatedAt = readDate(
    metadataObject.value,
    "updatedAt",
    "createdCanonicalComic.metadata",
  );
  if (isErr(metadataUpdatedAt)) {
    return metadataUpdatedAt;
  }
  const primaryTitleCreatedAt = readDate(
    primaryTitleObject.value,
    "createdAt",
    "createdCanonicalComic.primaryTitle",
  );
  if (isErr(primaryTitleCreatedAt)) {
    return primaryTitleCreatedAt;
  }

  return ok({
    comic: {
      id: comicId.value,
      normalizedTitle: normalizedTitle.value,
      originHint: originHint.value as ComicOriginHint,
      createdAt: comicCreatedAt.value,
      updatedAt: comicUpdatedAt.value,
    },
    metadata: withOptional(
      withOptional(
        withOptional(
          withOptional(
            withOptional(
              {
                comicId: metadataComicId.value,
                title: metadataTitle.value,
                createdAt: metadataCreatedAt.value,
                updatedAt: metadataUpdatedAt.value,
              },
              "description",
              metadataDescription.value,
            ),
            "coverPageId",
            metadataCoverPageId.value,
          ),
          "coverStorageObjectId",
          metadataCoverStorageObjectId.value,
        ),
        "authorName",
        metadataAuthorName.value,
      ),
      "metadata",
      metadataPayload.value,
    ),
    primaryTitle: withOptional(
      withOptional(
        withOptional(
          {
            id: primaryTitleId.value,
            comicId: primaryTitleComicId.value,
            title: primaryTitleTitle.value,
            normalizedTitle: primaryTitleNormalizedTitle.value,
            titleKind: primaryTitleKind.value as ComicTitle["titleKind"],
            createdAt: primaryTitleCreatedAt.value,
          },
          "locale",
          primaryTitleLocale.value,
        ),
        "sourcePlatformId",
        primaryTitleSourcePlatformId.value,
      ),
      "sourceLinkId",
      primaryTitleSourceLinkId.value,
    ),
  });
}

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

      const idempotencyKey =
        input.idempotencyKey === undefined
          ? ok(undefined)
          : parseIdempotencyKey(input.idempotencyKey);
      if (isErr(idempotencyKey)) {
        return idempotencyKey;
      }

      const canonicalInput = canonicalizeCreateCanonicalComicInput(
        input,
        normalizedTitle.value,
      );
      const inputHash = parseInputHash(hashCanonicalInput(canonicalInput));
      if (isErr(inputHash)) {
        return inputHash;
      }

      return this.dependencies.transaction.runInTransaction(async () => {
        const now = this.dependencies.clock.now();

        if (idempotencyKey.value !== undefined) {
          const existing = await this.dependencies.repositories.operationIdempotency.get({
            operationName: CREATE_CANONICAL_COMIC_OPERATION_NAME,
            idempotencyKey: idempotencyKey.value,
          });
          if (isErr(existing)) {
            return existing;
          }

          if (existing.value !== null) {
            if (existing.value.status !== "completed") {
              return fail(
                "INTERNAL_ERROR",
                "Idempotency key is not replayable.",
                {
                  operationName: CREATE_CANONICAL_COMIC_OPERATION_NAME,
                  idempotencyKey: idempotencyKey.value,
                  status: existing.value.status,
                },
              );
            }

            if (existing.value.inputHash !== inputHash.value) {
              return fail(
                "IDEMPOTENCY_CONFLICT",
                "Idempotency key already exists for different canonical input.",
                {
                  operationName: CREATE_CANONICAL_COMIC_OPERATION_NAME,
                  idempotencyKey: idempotencyKey.value,
                },
              );
            }

            if (
              existing.value.resultType !== CREATED_CANONICAL_COMIC_RESULT_TYPE
              || existing.value.resultSchemaVersion !== IDEMPOTENCY_RESULT_SCHEMA_VERSION
              || existing.value.resultResourceId === undefined
              || existing.value.resultJson === undefined
            ) {
              return fail(
                "INTERNAL_ERROR",
                "Stored idempotency replay payload is invalid.",
                {
                  operationName: CREATE_CANONICAL_COMIC_OPERATION_NAME,
                  idempotencyKey: idempotencyKey.value,
                },
              );
            }

            return mapReplayToCreatedCanonicalComic(existing.value.resultJson);
          }

          const claimed = await this.dependencies.repositories.operationIdempotency.createInProgress({
            operationName: CREATE_CANONICAL_COMIC_OPERATION_NAME,
            idempotencyKey: idempotencyKey.value,
            inputHash: inputHash.value,
            createdAt: now,
            updatedAt: now,
          });
          if (isErr(claimed)) {
            return claimed;
          }
        }

        const comicId = parseComicId(this.dependencies.idGenerator.create());
        if (isErr(comicId)) {
          return comicId;
        }

        const comic = await this.dependencies.repositories.comics.create({
          id: comicId.value,
          normalizedTitle: normalizedTitle.value,
          originHint: canonicalInput.originHint,
          createdAt: now,
          updatedAt: now,
        });
        if (isErr(comic)) {
          return comic;
        }

        const metadata = await this.dependencies.repositories.comicMetadata.create(
          withOptional(
            withOptional(
              {
                comicId: comicId.value,
                title: title.value,
                createdAt: now,
                updatedAt: now,
              },
              "description",
              canonicalInput.description,
            ),
            "authorName",
            canonicalInput.authorName,
          ),
        );
        if (isErr(metadata)) {
          return metadata;
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

        const storedPrimaryTitle = await this.dependencies.repositories.comicTitles.addTitle(
          primaryTitle.value,
        );
        if (isErr(storedPrimaryTitle)) {
          return storedPrimaryTitle;
        }

        const created: CreatedCanonicalComic = {
          comic: comic.value,
          metadata: metadata.value,
          primaryTitle: storedPrimaryTitle.value,
        };

        if (idempotencyKey.value !== undefined) {
          const completed = await this.dependencies.repositories.operationIdempotency.markCompleted({
            operationName: CREATE_CANONICAL_COMIC_OPERATION_NAME,
            idempotencyKey: idempotencyKey.value,
            inputHash: inputHash.value,
            resultType: CREATED_CANONICAL_COMIC_RESULT_TYPE,
            resultResourceId: created.comic.id,
            resultJson: serializeCreatedCanonicalComicReplay(created),
            resultSchemaVersion: IDEMPOTENCY_RESULT_SCHEMA_VERSION,
            updatedAt: now,
          });
          if (isErr(completed)) {
            return completed;
          }
        }

        return ok(created);
      });
    } catch (cause) {
      return unexpectedFailure("CreateCanonicalComic failed.", cause);
    }
  }
}
