import { randomUUID } from "node:crypto";

import { type Kysely } from "kysely";

import {
  parseDisplayTitle,
  parseNormalizedTitle,
  type AddComicTitleInput,
  type Comic,
  type ComicMetadata,
  type ComicTitle,
  type CreateComicInput,
  type CreateComicMetadataInput,
} from "../domain/comic.js";
import {
  type Chapter,
  type ChapterTreeNode,
  type ListChapterChildrenInput,
  CHAPTER_KINDS,
} from "../domain/chapter.js";
import {
  DIAGNOSTICS_SCHEMA_VERSION,
  DIAGNOSTIC_AUTHORITIES,
  DIAGNOSTIC_LEVELS,
  type DiagnosticsEvent,
  type DiagnosticsQuery,
  type RecordDiagnosticsEventInput,
} from "../domain/diagnostics.js";
import {
  CREATE_CANONICAL_COMIC_OPERATION_NAME,
  CREATED_CANONICAL_COMIC_RESULT_TYPE,
  IDEMPOTENCY_RESULT_SCHEMA_VERSION,
  OPERATION_IDEMPOTENCY_STATUSES,
  parseIdempotencyKey,
  parseInputHash,
  type CompleteOperationIdempotencyInput,
  type CreateOperationIdempotencyInput,
  type GetOperationIdempotencyInput,
  type OperationIdempotencyRecord,
} from "../domain/idempotency.js";
import {
  parseChapterId,
  parseChapterSourceLinkId,
  parseComicId,
  parseComicTitleId,
  parseDiagnosticsEventId,
  parsePageId,
  parsePageOrderId,
  parsePageOrderItemId,
  parseReaderSessionId,
  parseSourceLinkId,
  parseSourcePlatformId,
  parseStorageBackendId,
  parseStorageObjectId,
  parseStoragePlacementId,
  type ChapterId,
  type ComicId,
  type ComicTitleId,
  type PageId,
  type SourceLinkId,
  type StorageObjectId,
} from "../domain/identifiers.js";
import {
  PAGE_ORDER_KEYS,
  PAGE_ORDER_TYPES,
  type Page,
  type PageOrderWithItems,
  type SetUserPageOrderInput,
} from "../domain/page.js";
import {
  READER_MODES,
  type ReaderSession,
  type ReaderSessionPersistResult,
  type UpdateReaderPositionInput,
} from "../domain/reader.js";
import {
  SOURCE_LINK_CONFIDENCES,
  SOURCE_LINK_STATUSES,
  SOURCE_PLATFORM_KINDS,
  type ChapterSourceLink,
  type ProviderWorkRef,
  type SourceLink,
  type SourcePlatform,
} from "../domain/source.js";
import {
  STORAGE_BACKEND_KINDS,
  STORAGE_OBJECT_KINDS,
  STORAGE_PLACEMENT_ROLES,
  STORAGE_SYNC_STATUSES,
  type StorageObject,
  type StoragePlacement,
} from "../domain/storage.js";
import type {
  ChapterRepositoryPort,
  ChapterSourceLinkRepositoryPort,
  ComicMetadataRepositoryPort,
  ComicRepositoryPort,
  ComicTitleRepositoryPort,
  CoreRepositories,
  DiagnosticsEventRepositoryPort,
  OperationIdempotencyRepositoryPort,
  PageOrderRepositoryPort,
  PageRepositoryPort,
  ReaderSessionRepositoryPort,
  SourceLinkRepositoryPort,
  SourcePlatformRepositoryPort,
  StorageObjectRepositoryPort,
  StoragePlacementRepositoryPort,
} from "../ports/repositories.js";
import type { QueryExecutorProvider } from "../db/database.js";
import type { CoreDatabaseSchema } from "../db/schema.js";
import type { JsonObject } from "../shared/json.js";
import { createCoreError } from "../shared/errors.js";
import { err, isErr, ok, type Result } from "../shared/result.js";
import { ensureEnumValue, isoToDate, parseJsonObject, unwrapMappedResult } from "./mappers/common.js";

type Queryable = Kysely<CoreDatabaseSchema>;

function currentDb(executorProvider: QueryExecutorProvider): Queryable {
  return executorProvider.current() as Queryable;
}

function withOptional<
  TValue extends object,
  TKey extends string,
  TOptionalValue,
>(
  value: TValue,
  key: TKey,
  optionalValue: TOptionalValue | undefined,
): TValue & Partial<Record<TKey, TOptionalValue>> {
  if (optionalValue === undefined) {
    return value;
  }

  return {
    ...value,
    [key]: optionalValue,
  };
}

async function catchRepositoryError<TValue>(
  operation: () => Promise<Result<TValue>>,
): Promise<Result<TValue>> {
  try {
    return await operation();
  } catch (cause) {
    return err(
      createCoreError({
        code: "INTERNAL_ERROR",
        message: "Repository operation failed.",
        cause,
      }),
    );
  }
}

function mapComic(row: CoreDatabaseSchema["comics"]): Result<Comic> {
  const id = parseComicId(row.id);
  if (isErr(id)) {
    return id;
  }

  const normalizedTitle = parseNormalizedTitle(row.normalized_title);
  if (isErr(normalizedTitle)) {
    return normalizedTitle;
  }

  const originHint = ensureEnumValue(row.origin_hint, ["unknown", "local", "remote", "mixed"], "origin_hint");
  if (isErr(originHint)) {
    return originHint;
  }

  const createdAt = isoToDate(row.created_at, "created_at");
  if (isErr(createdAt)) {
    return createdAt;
  }

  const updatedAt = isoToDate(row.updated_at, "updated_at");
  if (isErr(updatedAt)) {
    return updatedAt;
  }

  return ok({
    id: id.value,
    normalizedTitle: normalizedTitle.value,
    originHint: originHint.value,
    createdAt: createdAt.value,
    updatedAt: updatedAt.value,
  });
}

function mapComicMetadata(row: CoreDatabaseSchema["comic_metadata"]): Result<ComicMetadata> {
  const comicId = parseComicId(row.comic_id);
  if (isErr(comicId)) {
    return comicId;
  }

  const title = parseDisplayTitle(row.title);
  if (isErr(title)) {
    return title;
  }

  const coverPageId = row.cover_page_id === null ? ok(undefined) : parsePageId(row.cover_page_id);
  if (isErr(coverPageId)) {
    return coverPageId;
  }

  const coverStorageObjectId =
    row.cover_storage_object_id === null
      ? ok(undefined)
      : parseStorageObjectId(row.cover_storage_object_id);
  if (isErr(coverStorageObjectId)) {
    return coverStorageObjectId;
  }

  const metadata = parseJsonObject(row.metadata_json, "metadata_json");
  if (isErr(metadata)) {
    return metadata;
  }

  const createdAt = isoToDate(row.created_at, "created_at");
  if (isErr(createdAt)) {
    return createdAt;
  }

  const updatedAt = isoToDate(row.updated_at, "updated_at");
  if (isErr(updatedAt)) {
    return updatedAt;
  }

  return ok(withOptional(withOptional(withOptional(withOptional(withOptional({
    comicId: comicId.value,
    title: title.value,
    createdAt: createdAt.value,
    updatedAt: updatedAt.value,
  }, "description", row.description ?? undefined), "coverPageId", coverPageId.value), "coverStorageObjectId", coverStorageObjectId.value), "authorName", row.author_name ?? undefined), "metadata", metadata.value));
}

function mapComicTitle(row: CoreDatabaseSchema["comic_titles"]): Result<ComicTitle> {
  const id = parseComicTitleId(row.id);
  if (isErr(id)) {
    return id;
  }

  const comicId = parseComicId(row.comic_id);
  if (isErr(comicId)) {
    return comicId;
  }

  const title = parseDisplayTitle(row.title);
  if (isErr(title)) {
    return title;
  }

  const normalizedTitle = parseNormalizedTitle(row.normalized_title);
  if (isErr(normalizedTitle)) {
    return normalizedTitle;
  }

  const sourcePlatformId =
    row.source_platform_id === null ? ok(undefined) : parseSourcePlatformId(row.source_platform_id);
  if (isErr(sourcePlatformId)) {
    return sourcePlatformId;
  }

  const sourceLinkId =
    row.source_link_id === null ? ok(undefined) : parseSourceLinkId(row.source_link_id);
  if (isErr(sourceLinkId)) {
    return sourceLinkId;
  }

  const titleKind = ensureEnumValue(row.title_kind, ["primary", "alias", "translated", "source"], "title_kind");
  if (isErr(titleKind)) {
    return titleKind;
  }

  const createdAt = isoToDate(row.created_at, "created_at");
  if (isErr(createdAt)) {
    return createdAt;
  }

  return ok(withOptional(withOptional(withOptional({
    id: id.value,
    comicId: comicId.value,
    title: title.value,
    normalizedTitle: normalizedTitle.value,
    titleKind: titleKind.value,
    createdAt: createdAt.value,
  }, "locale", row.locale ?? undefined), "sourcePlatformId", sourcePlatformId.value), "sourceLinkId", sourceLinkId.value));
}

function mapChapter(row: CoreDatabaseSchema["chapters"]): Result<Chapter> {
  const id = parseChapterId(row.id);
  if (isErr(id)) {
    return id;
  }

  const comicId = parseComicId(row.comic_id);
  if (isErr(comicId)) {
    return comicId;
  }

  const parentChapterId =
    row.parent_chapter_id === null ? ok(undefined) : parseChapterId(row.parent_chapter_id);
  if (isErr(parentChapterId)) {
    return parentChapterId;
  }

  const chapterKind = ensureEnumValue(row.chapter_kind, CHAPTER_KINDS, "chapter_kind");
  if (isErr(chapterKind)) {
    return chapterKind;
  }

  const createdAt = isoToDate(row.created_at, "created_at");
  if (isErr(createdAt)) {
    return createdAt;
  }

  const updatedAt = isoToDate(row.updated_at, "updated_at");
  if (isErr(updatedAt)) {
    return updatedAt;
  }

  return ok(withOptional(withOptional(withOptional({
    id: id.value,
    comicId: comicId.value,
    chapterKind: chapterKind.value,
    chapterNumber: row.chapter_number,
    createdAt: createdAt.value,
    updatedAt: updatedAt.value,
  }, "parentChapterId", parentChapterId.value), "title", row.title ?? undefined), "displayLabel", row.display_label ?? undefined));
}

function mapPage(row: CoreDatabaseSchema["pages"]): Result<Page> {
  const id = parsePageId(row.id);
  if (isErr(id)) {
    return id;
  }

  const chapterId = parseChapterId(row.chapter_id);
  if (isErr(chapterId)) {
    return chapterId;
  }

  const storageObjectId =
    row.storage_object_id === null ? ok(undefined) : parseStorageObjectId(row.storage_object_id);
  if (isErr(storageObjectId)) {
    return storageObjectId;
  }

  const chapterSourceLinkId =
    row.chapter_source_link_id === null
      ? ok(undefined)
      : parseChapterSourceLinkId(row.chapter_source_link_id);
  if (isErr(chapterSourceLinkId)) {
    return chapterSourceLinkId;
  }

  const createdAt = isoToDate(row.created_at, "created_at");
  if (isErr(createdAt)) {
    return createdAt;
  }

  const updatedAt = isoToDate(row.updated_at, "updated_at");
  if (isErr(updatedAt)) {
    return updatedAt;
  }

  return ok(withOptional(withOptional(withOptional(withOptional(withOptional(withOptional({
    id: id.value,
    chapterId: chapterId.value,
    pageIndex: row.page_index,
    createdAt: createdAt.value,
    updatedAt: updatedAt.value,
  }, "storageObjectId", storageObjectId.value), "chapterSourceLinkId", chapterSourceLinkId.value), "mimeType", row.mime_type ?? undefined), "width", row.width ?? undefined), "height", row.height ?? undefined), "checksum", row.checksum ?? undefined));
}

function mapSourcePlatform(row: CoreDatabaseSchema["source_platforms"]): Result<SourcePlatform> {
  const id = parseSourcePlatformId(row.id);
  if (isErr(id)) {
    return id;
  }

  const kind = ensureEnumValue(row.kind, SOURCE_PLATFORM_KINDS, "kind");
  if (isErr(kind)) {
    return kind;
  }

  const createdAt = isoToDate(row.created_at, "created_at");
  if (isErr(createdAt)) {
    return createdAt;
  }

  const updatedAt = isoToDate(row.updated_at, "updated_at");
  if (isErr(updatedAt)) {
    return updatedAt;
  }

  return ok({
    id: id.value,
    canonicalKey: row.canonical_key,
    displayName: row.display_name,
    kind: kind.value,
    isEnabled: row.is_enabled === 1,
    createdAt: createdAt.value,
    updatedAt: updatedAt.value,
  });
}

function mapSourceLink(row: CoreDatabaseSchema["source_links"]): Result<SourceLink> {
  const id = parseSourceLinkId(row.id);
  if (isErr(id)) {
    return id;
  }

  const comicId = parseComicId(row.comic_id);
  if (isErr(comicId)) {
    return comicId;
  }

  const sourcePlatformId = parseSourcePlatformId(row.source_platform_id);
  if (isErr(sourcePlatformId)) {
    return sourcePlatformId;
  }

  const linkStatus = ensureEnumValue(row.link_status, SOURCE_LINK_STATUSES, "link_status");
  if (isErr(linkStatus)) {
    return linkStatus;
  }

  const confidence = ensureEnumValue(row.confidence, SOURCE_LINK_CONFIDENCES, "confidence");
  if (isErr(confidence)) {
    return confidence;
  }

  const createdAt = isoToDate(row.created_at, "created_at");
  if (isErr(createdAt)) {
    return createdAt;
  }

  const updatedAt = isoToDate(row.updated_at, "updated_at");
  if (isErr(updatedAt)) {
    return updatedAt;
  }

  return ok(withOptional(withOptional({
    id: id.value,
    comicId: comicId.value,
    sourcePlatformId: sourcePlatformId.value,
    remoteWorkId: row.remote_work_id,
    linkStatus: linkStatus.value,
    confidence: confidence.value,
    createdAt: createdAt.value,
    updatedAt: updatedAt.value,
  }, "remoteUrl", row.remote_url ?? undefined), "displayTitle", row.display_title ?? undefined));
}

function mapChapterSourceLink(
  row: CoreDatabaseSchema["chapter_source_links"],
): Result<ChapterSourceLink> {
  const id = parseChapterSourceLinkId(row.id);
  if (isErr(id)) {
    return id;
  }

  const chapterId = parseChapterId(row.chapter_id);
  if (isErr(chapterId)) {
    return chapterId;
  }

  const sourceLinkId = parseSourceLinkId(row.source_link_id);
  if (isErr(sourceLinkId)) {
    return sourceLinkId;
  }

  const linkStatus = ensureEnumValue(row.link_status, SOURCE_LINK_STATUSES, "link_status");
  if (isErr(linkStatus)) {
    return linkStatus;
  }

  const createdAt = isoToDate(row.created_at, "created_at");
  if (isErr(createdAt)) {
    return createdAt;
  }

  const updatedAt = isoToDate(row.updated_at, "updated_at");
  if (isErr(updatedAt)) {
    return updatedAt;
  }

  return ok(withOptional(withOptional({
    id: id.value,
    chapterId: chapterId.value,
    sourceLinkId: sourceLinkId.value,
    remoteChapterId: row.remote_chapter_id,
    linkStatus: linkStatus.value,
    createdAt: createdAt.value,
    updatedAt: updatedAt.value,
  }, "remoteUrl", row.remote_url ?? undefined), "remoteLabel", row.remote_label ?? undefined));
}

function mapStorageObject(row: CoreDatabaseSchema["storage_objects"]): Result<StorageObject> {
  const id = parseStorageObjectId(row.id);
  if (isErr(id)) {
    return id;
  }

  const objectKind = ensureEnumValue(row.object_kind, STORAGE_OBJECT_KINDS, "object_kind");
  if (isErr(objectKind)) {
    return objectKind;
  }

  const createdAt = isoToDate(row.created_at, "created_at");
  if (isErr(createdAt)) {
    return createdAt;
  }

  const updatedAt = isoToDate(row.updated_at, "updated_at");
  if (isErr(updatedAt)) {
    return updatedAt;
  }

  return ok(withOptional(withOptional(withOptional({
    id: id.value,
    objectKind: objectKind.value,
    createdAt: createdAt.value,
    updatedAt: updatedAt.value,
  }, "contentHash", row.content_hash ?? undefined), "sizeBytes", row.size_bytes ?? undefined), "mimeType", row.mime_type ?? undefined));
}

function mapStoragePlacement(
  row: CoreDatabaseSchema["storage_placements"],
): Result<StoragePlacement> {
  const id = parseStoragePlacementId(row.id);
  if (isErr(id)) {
    return id;
  }

  const storageObjectId = parseStorageObjectId(row.storage_object_id);
  if (isErr(storageObjectId)) {
    return storageObjectId;
  }

  const storageBackendId = parseStorageBackendId(row.storage_backend_id);
  if (isErr(storageBackendId)) {
    return storageBackendId;
  }

  const role = ensureEnumValue(row.role, STORAGE_PLACEMENT_ROLES, "role");
  if (isErr(role)) {
    return role;
  }

  const syncStatus = ensureEnumValue(row.sync_status, STORAGE_SYNC_STATUSES, "sync_status");
  if (isErr(syncStatus)) {
    return syncStatus;
  }

  const lastVerifiedAt =
    row.last_verified_at === null ? ok(undefined) : isoToDate(row.last_verified_at, "last_verified_at");
  if (isErr(lastVerifiedAt)) {
    return lastVerifiedAt;
  }

  const createdAt = isoToDate(row.created_at, "created_at");
  if (isErr(createdAt)) {
    return createdAt;
  }

  const updatedAt = isoToDate(row.updated_at, "updated_at");
  if (isErr(updatedAt)) {
    return updatedAt;
  }

  return ok(withOptional({
    id: id.value,
    storageObjectId: storageObjectId.value,
    storageBackendId: storageBackendId.value,
    objectKey: row.object_key,
    role: role.value,
    syncStatus: syncStatus.value,
    createdAt: createdAt.value,
    updatedAt: updatedAt.value,
  }, "lastVerifiedAt", lastVerifiedAt.value));
}

function mapReaderSession(
  row: CoreDatabaseSchema["reader_sessions"],
): Result<ReaderSession> {
  const id = parseReaderSessionId(row.id);
  if (isErr(id)) {
    return id;
  }

  const comicId = parseComicId(row.comic_id);
  if (isErr(comicId)) {
    return comicId;
  }

  const chapterId = parseChapterId(row.chapter_id);
  if (isErr(chapterId)) {
    return chapterId;
  }

  const pageId = row.page_id === null ? ok(undefined) : parsePageId(row.page_id);
  if (isErr(pageId)) {
    return pageId;
  }

  const sourceLinkId = row.source_link_id === null ? ok(undefined) : parseSourceLinkId(row.source_link_id);
  if (isErr(sourceLinkId)) {
    return sourceLinkId;
  }

  const chapterSourceLinkId =
    row.chapter_source_link_id === null
      ? ok(undefined)
      : parseChapterSourceLinkId(row.chapter_source_link_id);
  if (isErr(chapterSourceLinkId)) {
    return chapterSourceLinkId;
  }

  const readerMode = ensureEnumValue(row.reader_mode, READER_MODES, "reader_mode");
  if (isErr(readerMode)) {
    return readerMode;
  }

  const createdAt = isoToDate(row.created_at, "created_at");
  if (isErr(createdAt)) {
    return createdAt;
  }

  const updatedAt = isoToDate(row.updated_at, "updated_at");
  if (isErr(updatedAt)) {
    return updatedAt;
  }

  return ok(withOptional(withOptional(withOptional({
    id: id.value,
    comicId: comicId.value,
    chapterId: chapterId.value,
    pageIndex: row.page_index,
    readerMode: readerMode.value,
    createdAt: createdAt.value,
    updatedAt: updatedAt.value,
  }, "pageId", pageId.value), "sourceLinkId", sourceLinkId.value), "chapterSourceLinkId", chapterSourceLinkId.value));
}

function mapDiagnosticsEvent(
  row: CoreDatabaseSchema["diagnostics_events"],
): Result<DiagnosticsEvent> {
  const id = parseDiagnosticsEventId(row.id);
  if (isErr(id)) {
    return id;
  }

  if (row.schema_version !== DIAGNOSTICS_SCHEMA_VERSION) {
    return err(
      createCoreError({
        code: "INTERNAL_ERROR",
        message: "Invalid persisted diagnostics schema version.",
        details: {
          fieldName: "schema_version",
          rawValue: row.schema_version,
        },
      }),
    );
  }

  const level = ensureEnumValue(row.level, DIAGNOSTIC_LEVELS, "level");
  if (isErr(level)) {
    return level;
  }

  const authority =
    row.authority === null ? ok(undefined) : ensureEnumValue(row.authority, DIAGNOSTIC_AUTHORITIES, "authority");
  if (isErr(authority)) {
    return authority;
  }

  const comicId = row.comic_id === null ? ok(undefined) : parseComicId(row.comic_id);
  if (isErr(comicId)) {
    return comicId;
  }

  const sourcePlatformId =
    row.source_platform_id === null ? ok(undefined) : parseSourcePlatformId(row.source_platform_id);
  if (isErr(sourcePlatformId)) {
    return sourcePlatformId;
  }

  const payload = parseJsonObject(row.payload_json, "payload_json");
  if (isErr(payload)) {
    return payload;
  }

  const timestamp = isoToDate(row.timestamp, "timestamp");
  if (isErr(timestamp)) {
    return timestamp;
  }

  return ok(withOptional(withOptional(withOptional(withOptional(withOptional(withOptional({
    id: id.value,
    schemaVersion: DIAGNOSTICS_SCHEMA_VERSION,
    timestamp: timestamp.value,
    level: level.value,
    channel: row.channel,
    eventName: row.event_name,
    payload: payload.value ?? {},
  }, "correlationId", row.correlation_id ?? undefined), "boundary", row.boundary ?? undefined), "action", row.action ?? undefined), "authority", authority.value), "comicId", comicId.value), "sourcePlatformId", sourcePlatformId.value));
}

function mapOperationIdempotencyRecord(
  row: CoreDatabaseSchema["operation_idempotency"],
): Result<OperationIdempotencyRecord> {
  if (row.operation_name !== CREATE_CANONICAL_COMIC_OPERATION_NAME) {
    return err(
      createCoreError({
        code: "INTERNAL_ERROR",
        message: "Invalid persisted operation_name.",
        details: {
          fieldName: "operation_name",
          rawValue: row.operation_name,
        },
      }),
    );
  }

  const idempotencyKey = parseIdempotencyKey(row.idempotency_key);
  if (isErr(idempotencyKey)) {
    return idempotencyKey;
  }

  const inputHash = parseInputHash(row.input_hash);
  if (isErr(inputHash)) {
    return inputHash;
  }

  const status = ensureEnumValue(row.status, OPERATION_IDEMPOTENCY_STATUSES, "status");
  if (isErr(status)) {
    return status;
  }

  const createdAt = isoToDate(row.created_at, "created_at");
  if (isErr(createdAt)) {
    return createdAt;
  }

  const updatedAt = isoToDate(row.updated_at, "updated_at");
  if (isErr(updatedAt)) {
    return updatedAt;
  }

  if (status.value === "completed") {
    if (
      row.result_type === null
      || row.result_resource_id === null
      || row.result_json === null
      || row.result_schema_version === null
    ) {
      return err(
        createCoreError({
          code: "INTERNAL_ERROR",
          message: "Completed operation replay row is missing required result fields.",
          details: {
            fieldName: "operation_idempotency",
            operationName: row.operation_name,
            idempotencyKey: row.idempotency_key,
          },
        }),
      );
    }

    if (row.result_schema_version !== IDEMPOTENCY_RESULT_SCHEMA_VERSION) {
      return err(
        createCoreError({
          code: "INTERNAL_ERROR",
          message: "Invalid persisted operation replay schema version.",
          details: {
            fieldName: "result_schema_version",
            rawValue: row.result_schema_version,
          },
        }),
      );
    }

    const parsedJson = parseJsonObject(row.result_json, "result_json");
    if (isErr(parsedJson)) {
      return parsedJson;
    }

    if (parsedJson.value === undefined) {
      return err(
        createCoreError({
          code: "INTERNAL_ERROR",
          message: "Completed operation replay row is missing result_json.",
          details: {
            fieldName: "result_json",
            operationName: row.operation_name,
            idempotencyKey: row.idempotency_key,
          },
        }),
      );
    }

    if (row.result_type !== CREATED_CANONICAL_COMIC_RESULT_TYPE) {
      return err(
        createCoreError({
          code: "INTERNAL_ERROR",
          message: "Invalid persisted operation replay result type.",
          details: {
            fieldName: "result_type",
            rawValue: row.result_type,
          },
        }),
      );
    }

    const resultResourceId = parseComicId(row.result_resource_id);
    if (isErr(resultResourceId)) {
      return resultResourceId;
    }

    return ok({
      operationName: CREATE_CANONICAL_COMIC_OPERATION_NAME,
      idempotencyKey: idempotencyKey.value,
      inputHash: inputHash.value,
      status: "completed",
      resultType: CREATED_CANONICAL_COMIC_RESULT_TYPE,
      resultResourceId: resultResourceId.value,
      resultJson: parsedJson.value,
      resultSchemaVersion: IDEMPOTENCY_RESULT_SCHEMA_VERSION,
      createdAt: createdAt.value,
      updatedAt: updatedAt.value,
    });
  }

  return ok({
    operationName: CREATE_CANONICAL_COMIC_OPERATION_NAME,
    idempotencyKey: idempotencyKey.value,
    inputHash: inputHash.value,
    status: status.value,
    createdAt: createdAt.value,
    updatedAt: updatedAt.value,
  } as OperationIdempotencyRecord);
}

class SqliteComicRepository implements ComicRepositoryPort {
  constructor(private readonly executorProvider: QueryExecutorProvider) {}

  getById(id: ComicId): Promise<Result<Comic | null>> {
    return catchRepositoryError(async () => {
      const row = await currentDb(this.executorProvider)
        .selectFrom("comics")
        .selectAll()
        .where("id", "=", id)
        .executeTakeFirst();

      return row === undefined ? ok(null) : mapComic(row);
    });
  }

  listByNormalizedTitle(title: string): Promise<Result<readonly Comic[]>> {
    return catchRepositoryError(async () => {
      const rows = await currentDb(this.executorProvider)
        .selectFrom("comics")
        .selectAll()
        .where("normalized_title", "=", title)
        .orderBy("created_at", "asc")
        .orderBy("id", "asc")
        .execute();

      return ok(rows.map((row) => unwrapMappedResult(mapComic(row))));
    });
  }

  async getByNormalizedTitle(title: string): Promise<Result<Comic | null>> {
    return catchRepositoryError(async () => {
      const comics = await this.listByNormalizedTitle(title);
      if (isErr(comics)) {
        return comics;
      }

      return ok(comics.value[0] ?? null);
    });
  }

  async create(input: CreateComicInput): Promise<Result<Comic>> {
    return catchRepositoryError(async () => {
      await currentDb(this.executorProvider)
        .insertInto("comics")
        .values({
          id: input.id,
          normalized_title: input.normalizedTitle,
          origin_hint: input.originHint,
          created_at: input.createdAt.toISOString(),
          updated_at: input.updatedAt.toISOString(),
        })
        .execute();

      return ok({
        id: input.id,
        normalizedTitle: input.normalizedTitle,
        originHint: input.originHint,
        createdAt: input.createdAt,
        updatedAt: input.updatedAt,
      });
    });
  }
}

class SqliteComicMetadataRepository implements ComicMetadataRepositoryPort {
  constructor(private readonly executorProvider: QueryExecutorProvider) {}

  async getByComicId(comicId: ComicId): Promise<Result<ComicMetadata | null>> {
    return catchRepositoryError(async () => {
      const row = await currentDb(this.executorProvider)
        .selectFrom("comic_metadata")
        .selectAll()
        .where("comic_id", "=", comicId)
        .executeTakeFirst();

      return row === undefined ? ok(null) : mapComicMetadata(row);
    });
  }

  async create(input: CreateComicMetadataInput): Promise<Result<ComicMetadata>> {
    return catchRepositoryError(async () => {
      await currentDb(this.executorProvider)
        .insertInto("comic_metadata")
        .values({
          comic_id: input.comicId,
          title: input.title,
          description: input.description ?? null,
          cover_page_id: input.coverPageId ?? null,
          cover_storage_object_id: input.coverStorageObjectId ?? null,
          author_name: input.authorName ?? null,
          metadata_json: input.metadata === undefined ? null : JSON.stringify(input.metadata),
          created_at: input.createdAt.toISOString(),
          updated_at: input.updatedAt.toISOString(),
        })
        .execute();

      return ok(
        withOptional(
          withOptional(
            withOptional(
              withOptional(
                withOptional(
                  {
                    comicId: input.comicId,
                    title: input.title,
                    createdAt: input.createdAt,
                    updatedAt: input.updatedAt,
                  },
                  "description",
                  input.description,
                ),
                "coverPageId",
                input.coverPageId,
              ),
              "coverStorageObjectId",
              input.coverStorageObjectId,
            ),
            "authorName",
            input.authorName,
          ),
          "metadata",
          input.metadata,
        ),
      );
    });
  }

  async update(input: CreateComicMetadataInput): Promise<Result<ComicMetadata>> {
    return catchRepositoryError(async () => {
      await currentDb(this.executorProvider)
        .updateTable("comic_metadata")
        .set({
          title: input.title,
          description: input.description ?? null,
          cover_page_id: input.coverPageId ?? null,
          cover_storage_object_id: input.coverStorageObjectId ?? null,
          author_name: input.authorName ?? null,
          metadata_json: input.metadata === undefined ? null : JSON.stringify(input.metadata),
          updated_at: input.updatedAt.toISOString(),
        })
        .where("comic_id", "=", input.comicId)
        .execute();

      return ok(
        withOptional(
          withOptional(
            withOptional(
              withOptional(
                withOptional(
                  {
                    comicId: input.comicId,
                    title: input.title,
                    createdAt: input.createdAt,
                    updatedAt: input.updatedAt,
                  },
                  "description",
                  input.description,
                ),
                "coverPageId",
                input.coverPageId,
              ),
              "coverStorageObjectId",
              input.coverStorageObjectId,
            ),
            "authorName",
            input.authorName,
          ),
          "metadata",
          input.metadata,
        ),
      );
    });
  }
}

class SqliteComicTitleRepository implements ComicTitleRepositoryPort {
  constructor(private readonly executorProvider: QueryExecutorProvider) {}

  async listByComic(comicId: ComicId): Promise<Result<readonly ComicTitle[]>> {
    return catchRepositoryError(async () => {
      const rows = await currentDb(this.executorProvider)
        .selectFrom("comic_titles")
        .selectAll()
        .where("comic_id", "=", comicId)
        .orderBy("created_at", "asc")
        .execute();

      return ok(rows.map((row) => unwrapMappedResult(mapComicTitle(row))));
    });
  }

  async addTitle(input: AddComicTitleInput): Promise<Result<ComicTitle>> {
    return catchRepositoryError(async () => {
      await currentDb(this.executorProvider)
        .insertInto("comic_titles")
        .values({
          id: input.id,
          comic_id: input.comicId,
          title: input.title,
          normalized_title: input.normalizedTitle,
          locale: input.locale ?? null,
          source_platform_id: input.sourcePlatformId ?? null,
          source_link_id: input.sourceLinkId ?? null,
          title_kind: input.titleKind,
          created_at: input.createdAt.toISOString(),
        })
        .execute();

      return ok(
        withOptional(
          withOptional(
            withOptional(
              {
                id: input.id,
                comicId: input.comicId,
                title: input.title,
                normalizedTitle: input.normalizedTitle,
                titleKind: input.titleKind,
                createdAt: input.createdAt,
              },
              "locale",
              input.locale,
            ),
            "sourcePlatformId",
            input.sourcePlatformId,
          ),
          "sourceLinkId",
          input.sourceLinkId,
        ),
      );
    });
  }

  async removeTitle(id: ComicTitleId): Promise<Result<void>> {
    return catchRepositoryError(async () => {
      await currentDb(this.executorProvider)
        .deleteFrom("comic_titles")
        .where("id", "=", id)
        .execute();

      return ok(undefined);
    });
  }
}

class SqliteChapterRepository implements ChapterRepositoryPort {
  constructor(private readonly executorProvider: QueryExecutorProvider) {}

  async getById(id: ChapterId): Promise<Result<Chapter | null>> {
    return catchRepositoryError(async () => {
      const row = await currentDb(this.executorProvider)
        .selectFrom("chapters")
        .selectAll()
        .where("id", "=", id)
        .executeTakeFirst();

      return row === undefined ? ok(null) : mapChapter(row);
    });
  }

  async listTreeByComic(comicId: ComicId): Promise<Result<readonly ChapterTreeNode[]>> {
    const flatResult = await this.listByComic(comicId);
    if (isErr(flatResult)) {
      return flatResult;
    }

    const nodes = new Map<ChapterId, ChapterTreeNode>();
    const roots: ChapterTreeNode[] = [];

    for (const chapter of flatResult.value) {
      nodes.set(chapter.id, {
        chapter,
        children: [],
      });
    }

    for (const node of nodes.values()) {
      const parentId = node.chapter.parentChapterId;
      if (parentId === undefined) {
        roots.push(node);
        continue;
      }

      const parent = nodes.get(parentId);
      if (parent === undefined) {
        roots.push(node);
        continue;
      }

      (parent.children as ChapterTreeNode[]).push(node);
    }

    return ok(roots);
  }

  async listChildren(input: ListChapterChildrenInput): Promise<Result<readonly Chapter[]>> {
    return catchRepositoryError(async () => {
      const query = currentDb(this.executorProvider)
        .selectFrom("chapters")
        .selectAll()
        .where("comic_id", "=", input.comicId);

      const rows = input.parentChapterId === undefined
        ? await query.where("parent_chapter_id", "is", null).orderBy("chapter_number", "asc").execute()
        : await query.where("parent_chapter_id", "=", input.parentChapterId).orderBy("chapter_number", "asc").execute();

      return ok(rows.map((row) => unwrapMappedResult(mapChapter(row))));
    });
  }

  async listByComic(comicId: ComicId): Promise<Result<readonly Chapter[]>> {
    return catchRepositoryError(async () => {
      const rows = await currentDb(this.executorProvider)
        .selectFrom("chapters")
        .selectAll()
        .where("comic_id", "=", comicId)
        .orderBy("chapter_number", "asc")
        .orderBy("created_at", "asc")
        .execute();

      return ok(rows.map((row) => unwrapMappedResult(mapChapter(row))));
    });
  }
}

class SqlitePageRepository implements PageRepositoryPort {
  constructor(private readonly executorProvider: QueryExecutorProvider) {}

  async getById(id: PageId): Promise<Result<Page | null>> {
    return catchRepositoryError(async () => {
      const row = await currentDb(this.executorProvider)
        .selectFrom("pages")
        .selectAll()
        .where("id", "=", id)
        .executeTakeFirst();

      return row === undefined ? ok(null) : mapPage(row);
    });
  }

  async listByChapter(chapterId: ChapterId): Promise<Result<readonly Page[]>> {
    return catchRepositoryError(async () => {
      const rows = await currentDb(this.executorProvider)
        .selectFrom("pages")
        .selectAll()
        .where("chapter_id", "=", chapterId)
        .orderBy("page_index", "asc")
        .execute();

      return ok(rows.map((row) => unwrapMappedResult(mapPage(row))));
    });
  }
}

class SqlitePageOrderRepository implements PageOrderRepositoryPort {
  constructor(private readonly executorProvider: QueryExecutorProvider) {}

  async getActiveOrder(chapterId: ChapterId): Promise<Result<PageOrderWithItems | null>> {
    return catchRepositoryError(async () => {
      const orderRow = await currentDb(this.executorProvider)
        .selectFrom("page_orders")
        .selectAll()
        .where("chapter_id", "=", chapterId)
        .where("is_active", "=", 1)
        .executeTakeFirst();

      if (orderRow === undefined) {
        return ok(null);
      }

      const orderId = parsePageOrderId(orderRow.id);
      if (isErr(orderId)) {
        return orderId;
      }

      const orderKey = ensureEnumValue(orderRow.order_key, PAGE_ORDER_KEYS, "order_key");
      if (isErr(orderKey)) {
        return orderKey;
      }

      const orderType = ensureEnumValue(orderRow.order_type, PAGE_ORDER_TYPES, "order_type");
      if (isErr(orderType)) {
        return orderType;
      }

      const itemsRows = await currentDb(this.executorProvider)
        .selectFrom("page_order_items")
        .selectAll()
        .where("page_order_id", "=", orderRow.id)
        .orderBy("sort_index", "asc")
        .execute();

      const items = itemsRows.map((row) => ({
        id: unwrapMappedResult(parsePageOrderItemId(row.id)),
        pageOrderId: orderId.value,
        pageId: unwrapMappedResult(parsePageId(row.page_id)),
        sortIndex: row.sort_index,
        createdAt: unwrapMappedResult(isoToDate(row.created_at, "created_at")),
      }));

      return ok({
        order: {
          id: orderId.value,
          chapterId,
          orderKey: orderKey.value,
          orderType: orderType.value,
          isActive: orderRow.is_active === 1,
          pageCount: orderRow.page_count,
          createdAt: unwrapMappedResult(isoToDate(orderRow.created_at, "created_at")),
          updatedAt: unwrapMappedResult(isoToDate(orderRow.updated_at, "updated_at")),
        },
        items,
      });
    });
  }

  async setUserOrder(input: SetUserPageOrderInput): Promise<Result<PageOrderWithItems>> {
    return catchRepositoryError(async () => {
      const existingOrder = await currentDb(this.executorProvider)
        .selectFrom("page_orders")
        .select("id")
        .where("chapter_id", "=", input.chapterId)
        .where("is_active", "=", 1)
        .executeTakeFirst();

      if (existingOrder !== undefined) {
        await currentDb(this.executorProvider)
          .updateTable("page_orders")
          .set({
            is_active: 0,
            updated_at: input.updatedAt.toISOString(),
          })
          .where("chapter_id", "=", input.chapterId)
          .where("is_active", "=", 1)
          .execute();
      }

      const orderId = randomUUID();
      await currentDb(this.executorProvider)
        .insertInto("page_orders")
        .values({
          id: orderId,
          chapter_id: input.chapterId,
          order_key: "user",
          order_type: "user_override",
          is_active: 1,
          page_count: input.pageIds.length,
          created_at: input.updatedAt.toISOString(),
          updated_at: input.updatedAt.toISOString(),
        })
        .execute();

      for (const [index, pageId] of input.pageIds.entries()) {
        await currentDb(this.executorProvider)
          .insertInto("page_order_items")
          .values({
            id: randomUUID(),
            page_order_id: orderId,
            page_id: pageId,
            sort_index: index,
            created_at: input.updatedAt.toISOString(),
          })
          .execute();
      }

      const refreshedOrder = await this.getActiveOrder(input.chapterId);
      if (isErr(refreshedOrder)) {
        return refreshedOrder;
      }

      if (refreshedOrder.value === null) {
        return err(
          createCoreError({
            code: "INTERNAL_ERROR",
            message: "Active page order disappeared after write.",
          }),
        );
      }

      return ok(refreshedOrder.value);
    });
  }

  async resetToSourceOrder(chapterId: ChapterId): Promise<Result<PageOrderWithItems>> {
    return catchRepositoryError<PageOrderWithItems>(async () => {
      const pagesResult = await new SqlitePageRepository(this.executorProvider).listByChapter(chapterId);
      if (isErr(pagesResult)) {
        return pagesResult;
      }

      const updatedAt = new Date();
      return this.setUserOrder({
        chapterId,
        pageIds: pagesResult.value.map((page) => page.id),
        updatedAt,
      });
    });
  }
}

class SqliteReaderSessionRepository implements ReaderSessionRepositoryPort {
  constructor(private readonly executorProvider: QueryExecutorProvider) {}

  async getByComic(comicId: ComicId): Promise<Result<ReaderSession | null>> {
    return catchRepositoryError(async () => {
      const row = await currentDb(this.executorProvider)
        .selectFrom("reader_sessions")
        .selectAll()
        .where("comic_id", "=", comicId)
        .executeTakeFirst();

      return row === undefined ? ok(null) : mapReaderSession(row);
    });
  }

  async upsertPosition(
    input: UpdateReaderPositionInput,
  ): Promise<Result<ReaderSessionPersistResult>> {
    return catchRepositoryError<ReaderSessionPersistResult>(async () => {
      const existing = await this.getByComic(input.comicId);
      if (isErr(existing)) {
        return existing;
      }

      const now = new Date();
      if (existing.value !== null) {
        const session = existing.value;
        if (
          session.chapterId === input.chapterId &&
          session.pageId === input.pageId &&
          session.pageIndex === input.pageIndex &&
          session.readerMode === input.readerMode &&
          session.sourceLinkId === input.sourceLinkId &&
          session.chapterSourceLinkId === input.chapterSourceLinkId
        ) {
          return ok({
            session,
            status: "skipped_unchanged",
          });
        }

        await currentDb(this.executorProvider)
          .updateTable("reader_sessions")
          .set({
            chapter_id: input.chapterId,
            page_id: input.pageId ?? null,
            page_index: input.pageIndex,
            source_link_id: input.sourceLinkId ?? null,
            chapter_source_link_id: input.chapterSourceLinkId ?? null,
            reader_mode: input.readerMode,
            updated_at: now.toISOString(),
          })
          .where("comic_id", "=", input.comicId)
          .execute();

        return ok({
          session: withOptional(
            withOptional(
              withOptional(
                {
                  ...session,
                  chapterId: input.chapterId,
                  pageIndex: input.pageIndex,
                  readerMode: input.readerMode,
                  updatedAt: now,
                },
                "pageId",
                input.pageId,
              ),
              "sourceLinkId",
              input.sourceLinkId,
            ),
            "chapterSourceLinkId",
            input.chapterSourceLinkId,
          ),
          status: "written",
        });
      }

      const sessionId = parseReaderSessionId(randomUUID());
      if (isErr(sessionId)) {
        return sessionId;
      }

      await currentDb(this.executorProvider)
        .insertInto("reader_sessions")
        .values({
          id: sessionId.value,
          comic_id: input.comicId,
          chapter_id: input.chapterId,
          page_id: input.pageId ?? null,
          page_index: input.pageIndex,
          source_link_id: input.sourceLinkId ?? null,
          chapter_source_link_id: input.chapterSourceLinkId ?? null,
          reader_mode: input.readerMode,
          created_at: now.toISOString(),
          updated_at: now.toISOString(),
        })
        .execute();

      return ok({
        session: withOptional(
          withOptional(
            withOptional(
              {
                id: sessionId.value,
                comicId: input.comicId,
                chapterId: input.chapterId,
                pageIndex: input.pageIndex,
                readerMode: input.readerMode,
                createdAt: now,
                updatedAt: now,
              },
              "pageId",
              input.pageId,
            ),
            "sourceLinkId",
            input.sourceLinkId,
          ),
          "chapterSourceLinkId",
          input.chapterSourceLinkId,
        ),
        status: "written",
      });
    });
  }

  async clear(comicId: ComicId): Promise<Result<void>> {
    return catchRepositoryError(async () => {
      await currentDb(this.executorProvider)
        .deleteFrom("reader_sessions")
        .where("comic_id", "=", comicId)
        .execute();

      return ok(undefined);
    });
  }
}

class SqliteSourcePlatformRepository implements SourcePlatformRepositoryPort {
  constructor(private readonly executorProvider: QueryExecutorProvider) {}

  async getById(id: string): Promise<Result<SourcePlatform | null>> {
    return catchRepositoryError(async () => {
      const row = await currentDb(this.executorProvider)
        .selectFrom("source_platforms")
        .selectAll()
        .where("id", "=", id)
        .executeTakeFirst();

      return row === undefined ? ok(null) : mapSourcePlatform(row);
    });
  }

  async getByKey(canonicalKey: string): Promise<Result<SourcePlatform | null>> {
    return catchRepositoryError(async () => {
      const row = await currentDb(this.executorProvider)
        .selectFrom("source_platforms")
        .selectAll()
        .where("canonical_key", "=", canonicalKey)
        .executeTakeFirst();

      return row === undefined ? ok(null) : mapSourcePlatform(row);
    });
  }

  async listEnabled(): Promise<Result<readonly SourcePlatform[]>> {
    return catchRepositoryError(async () => {
      const rows = await currentDb(this.executorProvider)
        .selectFrom("source_platforms")
        .selectAll()
        .where("is_enabled", "=", 1)
        .orderBy("canonical_key", "asc")
        .execute();

      return ok(rows.map((row) => unwrapMappedResult(mapSourcePlatform(row))));
    });
  }
}

class SqliteSourceLinkRepository implements SourceLinkRepositoryPort {
  constructor(private readonly executorProvider: QueryExecutorProvider) {}

  async getById(id: SourceLinkId): Promise<Result<SourceLink | null>> {
    return catchRepositoryError(async () => {
      const row = await currentDb(this.executorProvider)
        .selectFrom("source_links")
        .selectAll()
        .where("id", "=", id)
        .executeTakeFirst();

      return row === undefined ? ok(null) : mapSourceLink(row);
    });
  }

  async listByComic(comicId: ComicId): Promise<Result<readonly SourceLink[]>> {
    return catchRepositoryError(async () => {
      const rows = await currentDb(this.executorProvider)
        .selectFrom("source_links")
        .selectAll()
        .where("comic_id", "=", comicId)
        .orderBy("created_at", "asc")
        .execute();

      return ok(rows.map((row) => unwrapMappedResult(mapSourceLink(row))));
    });
  }

  async findByProviderWork(input: ProviderWorkRef): Promise<Result<SourceLink | null>> {
    return catchRepositoryError(async () => {
      const row = await currentDb(this.executorProvider)
        .selectFrom("source_links")
        .selectAll()
        .where("source_platform_id", "=", input.sourcePlatformId)
        .where("remote_work_id", "=", input.remoteWorkId)
        .executeTakeFirst();

      return row === undefined ? ok(null) : mapSourceLink(row);
    });
  }
}

class SqliteChapterSourceLinkRepository implements ChapterSourceLinkRepositoryPort {
  constructor(private readonly executorProvider: QueryExecutorProvider) {}

  async listByChapter(chapterId: ChapterId): Promise<Result<readonly ChapterSourceLink[]>> {
    return catchRepositoryError(async () => {
      const rows = await currentDb(this.executorProvider)
        .selectFrom("chapter_source_links")
        .selectAll()
        .where("chapter_id", "=", chapterId)
        .orderBy("created_at", "asc")
        .execute();

      return ok(rows.map((row) => unwrapMappedResult(mapChapterSourceLink(row))));
    });
  }

  async listBySourceLink(sourceLinkId: SourceLinkId): Promise<Result<readonly ChapterSourceLink[]>> {
    return catchRepositoryError(async () => {
      const rows = await currentDb(this.executorProvider)
        .selectFrom("chapter_source_links")
        .selectAll()
        .where("source_link_id", "=", sourceLinkId)
        .orderBy("created_at", "asc")
        .execute();

      return ok(rows.map((row) => unwrapMappedResult(mapChapterSourceLink(row))));
    });
  }
}

class SqliteStorageObjectRepository implements StorageObjectRepositoryPort {
  constructor(private readonly executorProvider: QueryExecutorProvider) {}

  async getObject(id: StorageObjectId): Promise<Result<StorageObject | null>> {
    return catchRepositoryError(async () => {
      const row = await currentDb(this.executorProvider)
        .selectFrom("storage_objects")
        .selectAll()
        .where("id", "=", id)
        .executeTakeFirst();

      return row === undefined ? ok(null) : mapStorageObject(row);
    });
  }
}

class SqliteStoragePlacementRepository implements StoragePlacementRepositoryPort {
  constructor(private readonly executorProvider: QueryExecutorProvider) {}

  async listPlacements(storageObjectId: StorageObjectId): Promise<Result<readonly StoragePlacement[]>> {
    return catchRepositoryError(async () => {
      const rows = await currentDb(this.executorProvider)
        .selectFrom("storage_placements")
        .selectAll()
        .where("storage_object_id", "=", storageObjectId)
        .orderBy("created_at", "asc")
        .execute();

      return ok(rows.map((row) => unwrapMappedResult(mapStoragePlacement(row))));
    });
  }
}

class SqliteDiagnosticsEventRepository implements DiagnosticsEventRepositoryPort {
  constructor(private readonly executorProvider: QueryExecutorProvider) {}

  async record(input: RecordDiagnosticsEventInput): Promise<Result<DiagnosticsEvent>> {
    return catchRepositoryError(async () => {
      const schemaVersion = input.schemaVersion ?? DIAGNOSTICS_SCHEMA_VERSION;
      await currentDb(this.executorProvider)
        .insertInto("diagnostics_events")
        .values({
          id: input.id,
          schema_version: schemaVersion,
          timestamp: input.timestamp.toISOString(),
          level: input.level,
          channel: input.channel,
          event_name: input.eventName,
          correlation_id: input.correlationId ?? null,
          boundary: input.boundary ?? null,
          action: input.action ?? null,
          authority: input.authority ?? null,
          comic_id: input.comicId ?? null,
          source_platform_id: input.sourcePlatformId ?? null,
          payload_json: JSON.stringify(input.payload),
        })
        .execute();

      return ok({
        ...input,
        schemaVersion,
      });
    });
  }

  async query(input: DiagnosticsQuery): Promise<Result<readonly DiagnosticsEvent[]>> {
    return catchRepositoryError(async () => {
      let query = currentDb(this.executorProvider)
        .selectFrom("diagnostics_events")
        .selectAll()
        .orderBy("timestamp", "desc");

      if (input.level !== undefined) {
        query = query.where("level", "=", input.level);
      }

      if (input.channel !== undefined) {
        query = query.where("channel", "=", input.channel);
      }

      if (input.correlationId !== undefined) {
        query = query.where("correlation_id", "=", input.correlationId);
      }

      if (input.limit !== undefined) {
        query = query.limit(input.limit);
      }

      const rows = await query.execute();
      return ok(rows.map((row) => unwrapMappedResult(mapDiagnosticsEvent(row))));
    });
  }
}

class SqliteOperationIdempotencyRepository
implements OperationIdempotencyRepositoryPort {
  constructor(private readonly executorProvider: QueryExecutorProvider) {}

  async get(
    input: GetOperationIdempotencyInput,
  ): Promise<Result<OperationIdempotencyRecord | null>> {
    return catchRepositoryError(async () => {
      const existing = await currentDb(this.executorProvider)
        .selectFrom("operation_idempotency")
        .selectAll()
        .where("operation_name", "=", input.operationName)
        .where("idempotency_key", "=", input.idempotencyKey)
        .executeTakeFirst();

      return existing === undefined ? ok(null) : mapOperationIdempotencyRecord(existing);
    });
  }

  async createInProgress(
    input: CreateOperationIdempotencyInput,
  ): Promise<Result<OperationIdempotencyRecord>> {
    return catchRepositoryError(async () => {
      await currentDb(this.executorProvider)
        .insertInto("operation_idempotency")
        .values({
          operation_name: input.operationName,
          idempotency_key: input.idempotencyKey,
          input_hash: input.inputHash,
          status: "in_progress",
          result_type: null,
          result_resource_id: null,
          result_json: null,
          result_schema_version: null,
          created_at: input.createdAt.toISOString(),
          updated_at: input.createdAt.toISOString(),
        })
        .execute();

      return ok({
        operationName: input.operationName,
        idempotencyKey: input.idempotencyKey,
        inputHash: input.inputHash,
        status: "in_progress",
        createdAt: input.createdAt,
        updatedAt: input.createdAt,
      });
    });
  }

  async markCompleted(
    input: CompleteOperationIdempotencyInput,
  ): Promise<Result<OperationIdempotencyRecord>> {
    return catchRepositoryError(async () => {
      await currentDb(this.executorProvider)
        .updateTable("operation_idempotency")
        .set({
          status: "completed",
          result_type: CREATED_CANONICAL_COMIC_RESULT_TYPE,
          result_resource_id: input.resultResourceId,
          result_json: JSON.stringify(input.resultJson),
          result_schema_version: IDEMPOTENCY_RESULT_SCHEMA_VERSION,
          updated_at: input.updatedAt.toISOString(),
        })
        .where("operation_name", "=", input.operationName)
        .where("idempotency_key", "=", input.idempotencyKey)
        .where("input_hash", "=", input.inputHash)
        .where("status", "=", "in_progress")
        .execute();

      const persisted = await this.get({
        operationName: input.operationName,
        idempotencyKey: input.idempotencyKey,
      });
      if (isErr(persisted)) {
        return persisted;
      }

      if (persisted.value === null) {
        return err(
          createCoreError({
            code: "INTERNAL_ERROR",
            message: "Completed operation replay row was not found after update.",
          }),
        );
      }

      return ok(persisted.value);
    });
  }

}

export function createCoreRepositories(
  executorProvider: QueryExecutorProvider,
): CoreRepositories {
  return {
    comics: new SqliteComicRepository(executorProvider),
    comicMetadata: new SqliteComicMetadataRepository(executorProvider),
    comicTitles: new SqliteComicTitleRepository(executorProvider),
    chapters: new SqliteChapterRepository(executorProvider),
    pages: new SqlitePageRepository(executorProvider),
    pageOrders: new SqlitePageOrderRepository(executorProvider),
    readerSessions: new SqliteReaderSessionRepository(executorProvider),
    sourcePlatforms: new SqliteSourcePlatformRepository(executorProvider),
    sourceLinks: new SqliteSourceLinkRepository(executorProvider),
    chapterSourceLinks: new SqliteChapterSourceLinkRepository(executorProvider),
    storageObjects: new SqliteStorageObjectRepository(executorProvider),
    storagePlacements: new SqliteStoragePlacementRepository(executorProvider),
    diagnosticsEvents: new SqliteDiagnosticsEventRepository(executorProvider),
    operationIdempotency: new SqliteOperationIdempotencyRepository(executorProvider),
  };
}
