import type { Brand } from "../shared/brand.js";
import type { JsonObject } from "../shared/json.js";
import type { Result } from "../shared/result.js";
import { parseRequiredText } from "../shared/validation.js";

export const OPERATION_IDEMPOTENCY_STATUSES = [
  "in_progress",
  "completed",
  "failed",
] as const;

export type OperationIdempotencyStatus =
  (typeof OPERATION_IDEMPOTENCY_STATUSES)[number];

export const CREATE_CANONICAL_COMIC_OPERATION_NAME = "CreateCanonicalComic";
export const CREATED_CANONICAL_COMIC_RESULT_TYPE = "CreatedCanonicalComic";
export const IDEMPOTENCY_RESULT_SCHEMA_VERSION = "1.0.0" as const;

export type IdempotencyKey = Brand<string, "IdempotencyKey">;
export type InputHash = Brand<string, "InputHash">;

export interface OperationIdempotencyRecord {
  readonly operationName: string;
  readonly idempotencyKey: IdempotencyKey;
  readonly inputHash: InputHash;
  readonly status: OperationIdempotencyStatus;
  readonly resultType?: string;
  readonly resultResourceId?: string;
  readonly resultJson?: JsonObject;
  readonly resultSchemaVersion?: string;
  readonly createdAt: Date;
  readonly updatedAt: Date;
}

export interface GetOperationIdempotencyInput {
  readonly operationName: string;
  readonly idempotencyKey: IdempotencyKey;
}

export interface CreateOperationIdempotencyInput {
  readonly operationName: string;
  readonly idempotencyKey: IdempotencyKey;
  readonly inputHash: InputHash;
  readonly createdAt: Date;
  readonly updatedAt: Date;
}

export interface CompleteOperationIdempotencyInput {
  readonly operationName: string;
  readonly idempotencyKey: IdempotencyKey;
  readonly inputHash: InputHash;
  readonly resultType: string;
  readonly resultResourceId: string;
  readonly resultJson: JsonObject;
  readonly resultSchemaVersion: string;
  readonly updatedAt: Date;
}

export function parseIdempotencyKey(value: string): Result<IdempotencyKey> {
  return parseRequiredText<"IdempotencyKey">(value, "idempotencyKey");
}

export function parseInputHash(value: string): Result<InputHash> {
  return parseRequiredText<"InputHash">(value, "inputHash");
}
