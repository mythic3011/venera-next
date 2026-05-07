import { z } from "zod";

export {
  API_ERROR_CODES,
  ApiErrorCodeSchema,
  ApiErrorResponseSchema,
  ApiErrorSchema,
  type ApiError,
  type ApiErrorCode,
  type ApiErrorResponse,
} from "./errors.js";
export {
  ComicOriginHintSchema,
  ComicTitleKindSchema,
  COMICS_CREATE_PATH,
  CreateComicRequestSchema,
  CreateComicResponseSchema,
  CreateComicRoute,
  CreatedComicDtoSchema,
  CreatedComicMetadataDtoSchema,
  CreatedComicPrimaryTitleDtoSchema,
  mapCreatedCanonicalComicToDto,
  type CreateComicRequest,
  type CreateComicResponse,
  type CreatedCanonicalComicSource,
  type CreatedComicDto,
  type CreatedComicMetadataDto,
  type CreatedComicPrimaryTitleDto,
} from "./comics.js";
export {
  JsonObjectSchema,
  JsonValueSchema,
  type JsonObject,
  type JsonPrimitive,
  type JsonValue,
} from "./json.js";
export {
  RUNTIME_CLOSE_PATH,
  RUNTIME_HEALTH_PATH,
  RUNTIME_OPEN_PATH,
  RuntimeCloseRequestSchema,
  RuntimeCloseResponseSchema,
  RuntimeCloseRoute,
  RuntimeHealthRequestSchema,
  RuntimeHealthResponseSchema,
  RuntimeHealthRoute,
  RuntimeOpenRequestSchema,
  RuntimeOpenResponseSchema,
  RuntimeOpenRoute,
  RuntimeSummarySchema,
  type HttpMethod,
  type RouteContract,
  type RuntimeCloseRequest,
  type RuntimeCloseResponse,
  type RuntimeHealthRequest,
  type RuntimeHealthResponse,
  type RuntimeOpenRequest,
  type RuntimeOpenResponse,
  type RuntimeSummary,
} from "./runtime.js";

import {
  API_ERROR_CODES,
  ApiErrorCodeSchema,
  ApiErrorResponseSchema,
} from "./errors.js";
import {
  COMICS_CREATE_PATH,
  CreateComicRequestSchema,
  CreateComicResponseSchema,
} from "./comics.js";
import {
  RUNTIME_CLOSE_PATH,
  RUNTIME_HEALTH_PATH,
  RUNTIME_OPEN_PATH,
} from "./runtime.js";

export const API_ROUTES = {
  runtimeHealth: RUNTIME_HEALTH_PATH,
  runtimeOpen: RUNTIME_OPEN_PATH,
  runtimeClose: RUNTIME_CLOSE_PATH,
  createComic: COMICS_CREATE_PATH,
} as const;

export const RUNTIME_ERROR_TABLE = {
  VALIDATION_FAILED: {
    status: 400,
    message: "Request validation failed.",
  },
  IDEMPOTENCY_KEY_PAYLOAD_MISMATCH: {
    status: 409,
    message: "Idempotency key was already used with different input.",
  },
  RUNTIME_NOT_OPEN: {
    status: 409,
    message: "Runtime instance is not open.",
  },
  RUNTIME_UNAVAILABLE: {
    status: 503,
    message: "Runtime is unavailable.",
  },
  RUNTIME_SHUTTING_DOWN: {
    status: 503,
    message: "Runtime is shutting down.",
  },
  INTERNAL: {
    status: 500,
    message: "Internal server error.",
  },
} as const;

export const runtimeErrorCodeSchema = ApiErrorCodeSchema;
export const isoDateTimeSchema = z.string().datetime({ offset: true });
export const runtimeStateSchema = z.enum([
  "closed",
  "open",
  "shutting_down",
]);
export const runtimeModeSchema = z.literal("demo-memory");
export const runtimePersistenceSchema = z.object({
  kind: z.literal("memory"),
  persisted: z.literal(false),
  notice: z.literal("not-persisted"),
}).strict();
export const runtimeSummarySchema = z.object({
  mode: runtimeModeSchema,
  state: runtimeStateSchema,
  persistence: runtimePersistenceSchema,
}).strict();
export const runtimeEnvelopeSchema = z.object({
  runtime: runtimeSummarySchema,
}).strict();

export const runtimeHealthResponseSchema = runtimeEnvelopeSchema;
export const runtimeOpenRequestSchema = z.object({}).strict();
export const runtimeOpenResponseSchema = runtimeEnvelopeSchema;
export const runtimeCloseRequestSchema = z.object({}).strict();
export const runtimeCloseResponseSchema = runtimeEnvelopeSchema;

export const comicOriginHintSchema = z.enum([
  "unknown",
  "local",
  "remote",
  "mixed",
]);
export const comicTitleKindSchema = z.enum([
  "primary",
  "source",
  "alias",
]);
export const comicDtoSchema = z.object({
  id: z.string().uuid(),
  normalizedTitle: z.string().min(1),
  originHint: comicOriginHintSchema,
  createdAt: isoDateTimeSchema,
  updatedAt: isoDateTimeSchema,
}).strict();
export const comicMetadataDtoSchema = z.object({
  comicId: z.string().uuid(),
  title: z.string().min(1),
  description: z.string().min(1).optional(),
  coverPageId: z.string().uuid().optional(),
  coverStorageObjectId: z.string().uuid().optional(),
  authorName: z.string().min(1).optional(),
  metadata: z.record(z.string(), z.json()).optional(),
  createdAt: isoDateTimeSchema,
  updatedAt: isoDateTimeSchema,
}).strict();
export const comicTitleDtoSchema = z.object({
  id: z.string().uuid(),
  comicId: z.string().uuid(),
  title: z.string().min(1),
  normalizedTitle: z.string().min(1),
  locale: z.string().min(1).optional(),
  sourcePlatformId: z.string().uuid().optional(),
  sourceLinkId: z.string().uuid().optional(),
  titleKind: comicTitleKindSchema,
  createdAt: isoDateTimeSchema,
}).strict();
export const createComicRequestSchema = CreateComicRequestSchema;
export const createComicResponseSchema = CreateComicResponseSchema;
export const apiErrorSchema = ApiErrorResponseSchema;

export type ApiRoute = (typeof API_ROUTES)[keyof typeof API_ROUTES];
export type RuntimeErrorCode = z.infer<typeof runtimeErrorCodeSchema>;
export type RuntimeSummaryDto = z.infer<typeof runtimeSummarySchema>;
export type RuntimeHealthResponseCompat = z.infer<typeof runtimeHealthResponseSchema>;
export type RuntimeOpenRequestCompat = z.infer<typeof runtimeOpenRequestSchema>;
export type RuntimeOpenResponseCompat = z.infer<typeof runtimeOpenResponseSchema>;
export type RuntimeCloseRequestCompat = z.infer<typeof runtimeCloseRequestSchema>;
export type RuntimeCloseResponseCompat = z.infer<typeof runtimeCloseResponseSchema>;
export type ComicDto = z.infer<typeof comicDtoSchema>;
export type ComicMetadataDto = z.infer<typeof comicMetadataDtoSchema>;
export type ComicTitleDto = z.infer<typeof comicTitleDtoSchema>;
