import type { JsonObject } from "./json.js";

export const CORE_ERROR_CODES = [
  "VALIDATION_ERROR",
  "NOT_FOUND",
  "DUPLICATE",
  "IDEMPOTENCY_CONFLICT",
  "FORBIDDEN",
  "UNAUTHORIZED",
  "STORAGE_ERROR",
  "WEBDAV_ERROR",
  "NETWORK_ERROR",
  "SOURCE_REPOSITORY_INDEX_INVALID",
  "SOURCE_PACKAGE_MANIFEST_INVALID",
  "SOURCE_PACKAGE_HASH_MISMATCH",
  "SOURCE_PACKAGE_IDENTITY_MISMATCH",
  "SOURCE_PACKAGE_ENTRYPOINT_MISSING",
  "SOURCE_PACKAGE_CHECKSUM_MISMATCH",
  "SOURCE_PACKAGE_API_UNSUPPORTED",
  "SOURCE_PACKAGE_TAXONOMY_INVALID",
  "TAG_TAXONOMY_INVALID",
  "TAG_MAPPING_INVALID",
  "TAG_MAPPING_AMBIGUOUS",
  "INCOMPATIBLE_SOURCE_UPDATE",
  "SOURCE_MANIFEST_INVALID",
  "SOURCE_PERMISSION_DENIED",
  "SOURCE_SANDBOX_VIOLATION",
  "SOURCE_RUNTIME_ERROR",
  "READER_UNRESOLVED_LOCAL_TARGET",
  "REMOTE_READER_TARGET_NOT_LINKED",
  "READER_INVALID_POSITION",
  "DOWNLOAD_FAILED",
  "MIGRATION_UNSAFE_DATA",
  "INTERNAL_ERROR",
] as const;

export type CoreErrorCode = (typeof CORE_ERROR_CODES)[number];

export interface CoreErrorOptions {
  readonly code: CoreErrorCode;
  readonly message: string;
  readonly details?: JsonObject;
  readonly cause?: unknown;
}

export class CoreError extends Error {
  readonly code: CoreErrorCode;
  readonly details: JsonObject | undefined;

  constructor(options: CoreErrorOptions) {
    super(options.message, options.cause === undefined
      ? undefined
      : { cause: options.cause });
    this.name = "CoreError";
    this.code = options.code;
    this.details = options.details;
  }
}

export function createCoreError(options: CoreErrorOptions): CoreError {
  return new CoreError(options);
}
