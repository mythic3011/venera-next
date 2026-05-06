import type { Brand } from "../shared/brand.js";
import type { JsonObject } from "../shared/json.js";
import { ok, type Result } from "../shared/result.js";
import {
  normalizeWhitespace,
  parseRequiredText,
} from "../shared/validation.js";
import type {
  ComicId,
  ComicTitleId,
  PageId,
  SourceLinkId,
  SourcePlatformId,
  StorageObjectId,
} from "./identifiers.js";

export const COMIC_ORIGIN_HINTS = [
  "unknown",
  "local",
  "remote",
  "mixed",
] as const;

export type ComicOriginHint = (typeof COMIC_ORIGIN_HINTS)[number];

export const COMIC_TITLE_KINDS = [
  "primary",
  "alias",
  "translated",
  "source",
] as const;

export type ComicTitleKind = (typeof COMIC_TITLE_KINDS)[number];

export type DisplayTitle = Brand<string, "DisplayTitle">;
export type NormalizedTitle = Brand<string, "NormalizedTitle">;

export interface Comic {
  readonly id: ComicId;
  readonly normalizedTitle: NormalizedTitle;
  readonly originHint: ComicOriginHint;
  readonly createdAt: Date;
  readonly updatedAt: Date;
}

export interface ComicMetadata {
  readonly comicId: ComicId;
  readonly title: DisplayTitle;
  readonly description?: string;
  readonly coverPageId?: PageId;
  readonly coverStorageObjectId?: StorageObjectId;
  readonly authorName?: string;
  readonly metadata?: JsonObject;
  readonly createdAt: Date;
  readonly updatedAt: Date;
}

export interface ComicTitle {
  readonly id: ComicTitleId;
  readonly comicId: ComicId;
  readonly title: DisplayTitle;
  readonly normalizedTitle: NormalizedTitle;
  readonly locale?: string;
  readonly sourcePlatformId?: SourcePlatformId;
  readonly sourceLinkId?: SourceLinkId;
  readonly titleKind: ComicTitleKind;
  readonly createdAt: Date;
}

export interface CreateComicInput {
  readonly id: ComicId;
  readonly normalizedTitle: NormalizedTitle;
  readonly originHint: ComicOriginHint;
  readonly createdAt: Date;
  readonly updatedAt: Date;
}

export interface CreateComicMetadataInput {
  readonly comicId: ComicId;
  readonly title: DisplayTitle;
  readonly description?: string;
  readonly coverPageId?: PageId;
  readonly coverStorageObjectId?: StorageObjectId;
  readonly authorName?: string;
  readonly metadata?: JsonObject;
  readonly createdAt: Date;
  readonly updatedAt: Date;
}

export interface AddComicTitleInput {
  readonly id: ComicTitleId;
  readonly comicId: ComicId;
  readonly title: DisplayTitle;
  readonly normalizedTitle: NormalizedTitle;
  readonly locale?: string;
  readonly sourcePlatformId?: SourcePlatformId;
  readonly sourceLinkId?: SourceLinkId;
  readonly titleKind: ComicTitleKind;
  readonly createdAt: Date;
}

export interface CreateCanonicalComicInput {
  readonly title: string;
  readonly description?: string;
  readonly authorName?: string;
  readonly originHint?: ComicOriginHint;
  readonly idempotencyKey?: string;
}

export interface CreatedCanonicalComic {
  readonly comic: Comic;
  readonly metadata: ComicMetadata;
  readonly primaryTitle: ComicTitle;
}

export function parseDisplayTitle(value: string): Result<DisplayTitle> {
  return parseRequiredText<"DisplayTitle">(value, "title");
}

export function normalizeTitle(value: string): string {
  return normalizeWhitespace(value).toLocaleLowerCase();
}

export function parseNormalizedTitle(value: string): Result<NormalizedTitle> {
  return parseRequiredText<"NormalizedTitle">(normalizeTitle(value), "normalizedTitle");
}

export function buildPrimaryComicTitle(input: {
  readonly id: ComicTitleId;
  readonly comicId: ComicId;
  readonly title: DisplayTitle;
  readonly normalizedTitle: NormalizedTitle;
  readonly createdAt: Date;
}): Result<ComicTitle> {
  return ok({
    id: input.id,
    comicId: input.comicId,
    title: input.title,
    normalizedTitle: input.normalizedTitle,
    titleKind: "primary",
    createdAt: input.createdAt,
  });
}
