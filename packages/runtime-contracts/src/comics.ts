import { z } from "zod";

import { ApiErrorResponseSchema } from "./errors.js";
import { JsonObjectSchema } from "./json.js";
import type { RouteContract } from "./runtime.js";

const trimmedStringSchema = z.string().trim().min(1);

function isIsoDateTimeString(value: string): boolean {
  if (!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/u.test(value)) {
    return false;
  }

  const date = new Date(value);
  return !Number.isNaN(date.getTime()) && date.toISOString() === value;
}

const IsoDateTimeStringSchema = z.string().refine(isIsoDateTimeString, {
  message: "Expected an ISO-8601 UTC datetime string.",
});

export const ComicOriginHintSchema = z.enum([
  "unknown",
  "local",
  "remote",
  "mixed",
]);

export const ComicTitleKindSchema = z.enum([
  "primary",
  "source",
  "alias",
]);

export const CreateComicRequestSchema = z.object({
  title: trimmedStringSchema,
  description: trimmedStringSchema.optional(),
  authorName: trimmedStringSchema.optional(),
  originHint: ComicOriginHintSchema.optional(),
  idempotencyKey: trimmedStringSchema.optional(),
}).strict();

export const CreatedComicDtoSchema = z.object({
  id: trimmedStringSchema,
  normalizedTitle: trimmedStringSchema,
  originHint: ComicOriginHintSchema,
  createdAt: IsoDateTimeStringSchema,
  updatedAt: IsoDateTimeStringSchema,
}).strict();

export const CreatedComicMetadataDtoSchema = z.object({
  comicId: trimmedStringSchema,
  title: trimmedStringSchema,
  description: trimmedStringSchema.optional(),
  coverPageId: trimmedStringSchema.optional(),
  coverStorageObjectId: trimmedStringSchema.optional(),
  authorName: trimmedStringSchema.optional(),
  metadata: JsonObjectSchema.optional(),
  createdAt: IsoDateTimeStringSchema,
  updatedAt: IsoDateTimeStringSchema,
}).strict();

export const CreatedComicPrimaryTitleDtoSchema = z.object({
  id: trimmedStringSchema,
  comicId: trimmedStringSchema,
  title: trimmedStringSchema,
  normalizedTitle: trimmedStringSchema,
  locale: trimmedStringSchema.optional(),
  sourcePlatformId: trimmedStringSchema.optional(),
  sourceLinkId: trimmedStringSchema.optional(),
  titleKind: ComicTitleKindSchema,
  createdAt: IsoDateTimeStringSchema,
}).strict();

export const CreateComicResponseSchema = z.object({
  comic: CreatedComicDtoSchema,
  metadata: CreatedComicMetadataDtoSchema,
  primaryTitle: CreatedComicPrimaryTitleDtoSchema,
}).strict();

export interface CreatedCanonicalComicSource {
  readonly comic: {
    readonly id: string;
    readonly normalizedTitle: string;
    readonly originHint: z.infer<typeof ComicOriginHintSchema>;
    readonly createdAt: Date;
    readonly updatedAt: Date;
  };
  readonly metadata: {
    readonly comicId: string;
    readonly title: string;
    readonly description?: string;
    readonly coverPageId?: string;
    readonly coverStorageObjectId?: string;
    readonly authorName?: string;
    readonly metadata?: z.infer<typeof JsonObjectSchema>;
    readonly createdAt: Date;
    readonly updatedAt: Date;
  };
  readonly primaryTitle: {
    readonly id: string;
    readonly comicId: string;
    readonly title: string;
    readonly normalizedTitle: string;
    readonly locale?: string;
    readonly sourcePlatformId?: string;
    readonly sourceLinkId?: string;
    readonly titleKind: z.infer<typeof ComicTitleKindSchema>;
    readonly createdAt: Date;
  };
}

export const COMICS_CREATE_PATH = "/api/comics";

export const CreateComicRoute: RouteContract<
  "POST",
  typeof COMICS_CREATE_PATH,
  z.infer<typeof CreateComicRequestSchema>,
  z.infer<typeof CreateComicResponseSchema>
> = {
  method: "POST",
  path: COMICS_CREATE_PATH,
  request: CreateComicRequestSchema,
  response: CreateComicResponseSchema,
  error: ApiErrorResponseSchema,
};

export function mapCreatedCanonicalComicToDto(
  created: CreatedCanonicalComicSource,
): z.infer<typeof CreateComicResponseSchema> {
  return {
    comic: {
      id: created.comic.id,
      normalizedTitle: created.comic.normalizedTitle,
      originHint: created.comic.originHint,
      createdAt: created.comic.createdAt.toISOString(),
      updatedAt: created.comic.updatedAt.toISOString(),
    },
    metadata: {
      comicId: created.metadata.comicId,
      title: created.metadata.title,
      description: created.metadata.description,
      coverPageId: created.metadata.coverPageId,
      coverStorageObjectId: created.metadata.coverStorageObjectId,
      authorName: created.metadata.authorName,
      metadata: created.metadata.metadata,
      createdAt: created.metadata.createdAt.toISOString(),
      updatedAt: created.metadata.updatedAt.toISOString(),
    },
    primaryTitle: {
      id: created.primaryTitle.id,
      comicId: created.primaryTitle.comicId,
      title: created.primaryTitle.title,
      normalizedTitle: created.primaryTitle.normalizedTitle,
      locale: created.primaryTitle.locale,
      sourcePlatformId: created.primaryTitle.sourcePlatformId,
      sourceLinkId: created.primaryTitle.sourceLinkId,
      titleKind: created.primaryTitle.titleKind,
      createdAt: created.primaryTitle.createdAt.toISOString(),
    },
  };
}

export type CreateComicRequest = z.infer<typeof CreateComicRequestSchema>;
export type CreatedComicDto = z.infer<typeof CreatedComicDtoSchema>;
export type CreatedComicMetadataDto = z.infer<typeof CreatedComicMetadataDtoSchema>;
export type CreatedComicPrimaryTitleDto = z.infer<typeof CreatedComicPrimaryTitleDtoSchema>;
export type CreateComicResponse = z.infer<typeof CreateComicResponseSchema>;
