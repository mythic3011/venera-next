import type { Brand } from "../shared/brand.js";
import { parseBrandedUuid } from "../shared/validation.js";

export type ComicId = Brand<string, "ComicId">;
export type ComicTitleId = Brand<string, "ComicTitleId">;
export type ChapterId = Brand<string, "ChapterId">;
export type PageId = Brand<string, "PageId">;
export type PageOrderId = Brand<string, "PageOrderId">;
export type PageOrderItemId = Brand<string, "PageOrderItemId">;
export type SourcePlatformId = Brand<string, "SourcePlatformId">;
export type SourceLinkId = Brand<string, "SourceLinkId">;
export type ChapterSourceLinkId = Brand<string, "ChapterSourceLinkId">;
export type StorageBackendId = Brand<string, "StorageBackendId">;
export type StorageObjectId = Brand<string, "StorageObjectId">;
export type StoragePlacementId = Brand<string, "StoragePlacementId">;
export type ReaderSessionId = Brand<string, "ReaderSessionId">;
export type DiagnosticsEventId = Brand<string, "DiagnosticsEventId">;

export const parseComicId = (value: string) =>
  parseBrandedUuid<"ComicId">(value, "comicId");

export const parseComicTitleId = (value: string) =>
  parseBrandedUuid<"ComicTitleId">(value, "comicTitleId");

export const parseChapterId = (value: string) =>
  parseBrandedUuid<"ChapterId">(value, "chapterId");

export const parsePageId = (value: string) =>
  parseBrandedUuid<"PageId">(value, "pageId");

export const parsePageOrderId = (value: string) =>
  parseBrandedUuid<"PageOrderId">(value, "pageOrderId");

export const parsePageOrderItemId = (value: string) =>
  parseBrandedUuid<"PageOrderItemId">(value, "pageOrderItemId");

export const parseSourcePlatformId = (value: string) =>
  parseBrandedUuid<"SourcePlatformId">(value, "sourcePlatformId");

export const parseSourceLinkId = (value: string) =>
  parseBrandedUuid<"SourceLinkId">(value, "sourceLinkId");

export const parseChapterSourceLinkId = (value: string) =>
  parseBrandedUuid<"ChapterSourceLinkId">(value, "chapterSourceLinkId");

export const parseStorageBackendId = (value: string) =>
  parseBrandedUuid<"StorageBackendId">(value, "storageBackendId");

export const parseStorageObjectId = (value: string) =>
  parseBrandedUuid<"StorageObjectId">(value, "storageObjectId");

export const parseStoragePlacementId = (value: string) =>
  parseBrandedUuid<"StoragePlacementId">(value, "storagePlacementId");

export const parseReaderSessionId = (value: string) =>
  parseBrandedUuid<"ReaderSessionId">(value, "readerSessionId");

export const parseDiagnosticsEventId = (value: string) =>
  parseBrandedUuid<"DiagnosticsEventId">(value, "diagnosticsEventId");
