import { z, type ZodIssue } from "zod";

import { createCoreError, type CoreErrorCode } from "../shared/errors.js";
import { err, ok, type Result } from "../shared/result.js";

const SHA256_PATTERN = /^[0-9A-Fa-f]{64}$/;
const ABSOLUTE_URL_PATTERN = /^[A-Za-z][A-Za-z\d+.-]*:/;
const SCHEME_RELATIVE_URL_PATTERN = /^\/\//;

const NON_EMPTY_TEXT_SCHEMA = z.string().trim().min(1);
const SHA256_SCHEMA = NON_EMPTY_TEXT_SCHEMA
  .regex(SHA256_PATTERN, "Expected a SHA-256 hex string.")
  .transform((value) => value.toLowerCase());

const TAG_NAMESPACE_VALUES = [
  "genre",
  "theme",
  "audience",
  "demographic",
  "character",
  "artist",
  "author",
  "language",
  "year",
  "format",
  "content_warning",
  "source_specific",
] as const;

const TAG_VALUE_TYPE_VALUES = [
  "enum",
  "number",
  "date",
  "text",
  "boolean",
] as const;

const TAG_MAPPING_CONFIDENCE_VALUES = [
  "manual",
  "auto_high",
  "auto_low",
] as const;

const SOURCE_REPOSITORY_PACKAGE_ENTRY_SCHEMA = z.strictObject({
  packageKey: NON_EMPTY_TEXT_SCHEMA,
  providerKey: NON_EMPTY_TEXT_SCHEMA,
  displayName: NON_EMPTY_TEXT_SCHEMA,
  version: NON_EMPTY_TEXT_SCHEMA,
  manifestUrl: NON_EMPTY_TEXT_SCHEMA,
  packageUrl: NON_EMPTY_TEXT_SCHEMA,
  sha256: SHA256_SCHEMA,
  minCoreVersion: NON_EMPTY_TEXT_SCHEMA,
  capabilities: z.array(NON_EMPTY_TEXT_SCHEMA),
  permissions: z.array(NON_EMPTY_TEXT_SCHEMA),
});

const SOURCE_REPOSITORY_INDEX_SCHEMA = z.strictObject({
  schemaVersion: NON_EMPTY_TEXT_SCHEMA,
  repositoryKey: NON_EMPTY_TEXT_SCHEMA,
  displayName: NON_EMPTY_TEXT_SCHEMA,
  updatedAt: NON_EMPTY_TEXT_SCHEMA,
  packages: z.array(SOURCE_REPOSITORY_PACKAGE_ENTRY_SCHEMA),
});

const SOURCE_PACKAGE_MANIFEST_SCHEMA = z.strictObject({
  schemaVersion: NON_EMPTY_TEXT_SCHEMA,
  packageKey: NON_EMPTY_TEXT_SCHEMA,
  providerKey: NON_EMPTY_TEXT_SCHEMA,
  displayName: NON_EMPTY_TEXT_SCHEMA,
  version: NON_EMPTY_TEXT_SCHEMA,
  runtime: z.strictObject({
    kind: NON_EMPTY_TEXT_SCHEMA,
    entrypoint: NON_EMPTY_TEXT_SCHEMA,
    apiVersion: NON_EMPTY_TEXT_SCHEMA,
  }),
  capabilities: z.array(NON_EMPTY_TEXT_SCHEMA),
  permissions: z.array(NON_EMPTY_TEXT_SCHEMA),
  integrity: z.strictObject({
    archiveSha256: SHA256_SCHEMA,
    entrypointSha256: SHA256_SCHEMA,
  }),
  endpoints: z.strictObject({
    baseUrl: NON_EMPTY_TEXT_SCHEMA,
  }).optional(),
  taxonomy: z.strictObject({
    mappingFiles: z.array(NON_EMPTY_TEXT_SCHEMA),
  }).optional(),
});

const SOURCE_PACKAGE_CHECKSUMS_SCHEMA = z.strictObject({
  files: z.array(
    z.strictObject({
      path: NON_EMPTY_TEXT_SCHEMA,
      sha256: SHA256_SCHEMA,
    }),
  ),
  packageSha256: SHA256_SCHEMA,
});

const CANONICAL_TAG_SCHEMA = z.strictObject({
  canonicalKey: NON_EMPTY_TEXT_SCHEMA,
  namespace: z.enum(TAG_NAMESPACE_VALUES),
  defaultLabel: NON_EMPTY_TEXT_SCHEMA,
  facet: NON_EMPTY_TEXT_SCHEMA.optional(),
  valueType: z.enum(TAG_VALUE_TYPE_VALUES).optional(),
  sortOrder: z.number().int().optional(),
});

const CANONICAL_TAGS_DOCUMENT_SCHEMA = z.strictObject({
  schemaVersion: NON_EMPTY_TEXT_SCHEMA,
  tags: z.array(CANONICAL_TAG_SCHEMA),
});

const LOCALIZED_TAG_LABELS_DOCUMENT_SCHEMA = z.strictObject({
  schemaVersion: NON_EMPTY_TEXT_SCHEMA,
  locale: NON_EMPTY_TEXT_SCHEMA,
  labels: z.record(NON_EMPTY_TEXT_SCHEMA, NON_EMPTY_TEXT_SCHEMA),
});

const PROVIDER_TAG_MAPPING_DOCUMENT_SCHEMA = z.strictObject({
  schemaVersion: NON_EMPTY_TEXT_SCHEMA,
  providerKey: NON_EMPTY_TEXT_SCHEMA,
  sourceLocale: NON_EMPTY_TEXT_SCHEMA,
  mappings: z.array(
    z.strictObject({
      remoteTagKey: NON_EMPTY_TEXT_SCHEMA,
      remoteLabel: NON_EMPTY_TEXT_SCHEMA,
      canonicalKey: NON_EMPTY_TEXT_SCHEMA,
      confidence: z.enum(TAG_MAPPING_CONFIDENCE_VALUES),
    }),
  ),
});

export type SourceRepositoryPackageEntry = z.infer<typeof SOURCE_REPOSITORY_PACKAGE_ENTRY_SCHEMA>;
export type SourceRepositoryIndex = z.infer<typeof SOURCE_REPOSITORY_INDEX_SCHEMA>;
export type SourcePackageManifest = z.infer<typeof SOURCE_PACKAGE_MANIFEST_SCHEMA>;
export type SourcePackageChecksums = z.infer<typeof SOURCE_PACKAGE_CHECKSUMS_SCHEMA>;
export type CanonicalTag = z.infer<typeof CANONICAL_TAG_SCHEMA>;
export type CanonicalTagsDocument = z.infer<typeof CANONICAL_TAGS_DOCUMENT_SCHEMA>;
export type LocalizedTagLabelsDocument = z.infer<typeof LOCALIZED_TAG_LABELS_DOCUMENT_SCHEMA>;
export type ProviderTagMappingDocument = z.infer<typeof PROVIDER_TAG_MAPPING_DOCUMENT_SCHEMA>;
export type TagNamespace = (typeof TAG_NAMESPACE_VALUES)[number];
export type TagValueType = (typeof TAG_VALUE_TYPE_VALUES)[number];
export type TagMappingConfidence = (typeof TAG_MAPPING_CONFIDENCE_VALUES)[number];

export interface SourceContractUrlPolicyOptions {
  readonly allowHttp?: boolean;
  readonly repositoryBaseUrl?: string;
}

export interface SourceRepositoryIndexValidationOptions {
  readonly urlPolicy?: SourceContractUrlPolicyOptions;
}

export interface SourcePackageManifestValidationOptions {
  readonly urlPolicy?: SourceContractUrlPolicyOptions;
}

export interface CanonicalKeyValidationOptions {
  readonly knownCanonicalKeys?: Iterable<string>;
}

export interface ProviderTagMappingValidationOptions extends CanonicalKeyValidationOptions {
  readonly expectedProviderKey?: string;
}

type ValidationIssue = {
  readonly path: string;
  readonly message: string;
};

function toIssuePath(path: readonly PropertyKey[]): string {
  if (path.length === 0) {
    return "$";
  }

  return path.reduce<string>((result, segment) => {
    if (typeof segment === "number") {
      return `${result}[${segment}]`;
    }

    return `${result}.${String(segment)}`;
  }, "$");
}

function createValidationError(
  code: CoreErrorCode,
  message: string,
  issues: readonly ValidationIssue[],
) {
  return createCoreError({
    code,
    message,
    details: {
      issues: issues.map((issue) => ({
        path: issue.path,
        message: issue.message,
      })),
    },
  });
}

function issuesFromZod(zodIssues: readonly ZodIssue[]): readonly ValidationIssue[] {
  return zodIssues.map((issue) => ({
    path: toIssuePath(issue.path),
    message: issue.message,
  }));
}

function failure<TValue>(
  code: CoreErrorCode,
  message: string,
  issues: readonly ValidationIssue[],
): Result<TValue> {
  return err(createValidationError(code, message, issues));
}

function normalizeKnownCanonicalKeys(
  knownCanonicalKeys: Iterable<string> | undefined,
): ReadonlySet<string> | null {
  if (knownCanonicalKeys === undefined) {
    return null;
  }

  return new Set(knownCanonicalKeys);
}

function validateUrlValue(
  rawValue: string,
  policy: SourceContractUrlPolicyOptions | undefined,
): ValidationIssue | null {
  const value = rawValue.trim();
  if (value.length === 0) {
    return {
      path: "$",
      message: "URL must not be empty.",
    };
  }

  if (SCHEME_RELATIVE_URL_PATTERN.test(value)) {
    return {
      path: "$",
      message: "Scheme-relative URLs are not allowed.",
    };
  }

  if (!ABSOLUTE_URL_PATTERN.test(value)) {
    if (policy?.repositoryBaseUrl !== undefined) {
      try {
        const resolvedUrl = new URL(value, policy.repositoryBaseUrl);
        const protocolIssue = validateResolvedUrlProtocol(resolvedUrl, policy);
        if (protocolIssue !== null) {
          return protocolIssue;
        }
      } catch {
        return {
          path: "$",
          message: "Relative URL could not be resolved against repositoryBaseUrl.",
        };
      }
    }

    return null;
  }

  let url: URL;
  try {
    url = new URL(value);
  } catch {
    return {
      path: "$",
      message: "Invalid absolute URL.",
    };
  }

  return validateResolvedUrlProtocol(url, policy);
}

function validateResolvedUrlProtocol(
  url: URL,
  policy: SourceContractUrlPolicyOptions | undefined,
): ValidationIssue | null {
  switch (url.protocol) {
    case "https:":
      return null;
    case "http:":
      return policy?.allowHttp === true
        ? null
        : {
          path: "$",
          message: "HTTP URLs require explicit allowHttp opt-in.",
        };
    case "file:":
    case "javascript:":
    case "data:":
      return {
        path: "$",
        message: `Protocol ${url.protocol} is not allowed.`,
      };
    default:
      return {
        path: "$",
        message: `Protocol ${url.protocol} is not allowed.`,
      };
  }
}

function collectDuplicateValues(values: readonly string[]): readonly string[] {
  const seen = new Set<string>();
  const duplicates = new Set<string>();
  for (const value of values) {
    if (seen.has(value)) {
      duplicates.add(value);
      continue;
    }

    seen.add(value);
  }

  return [...duplicates];
}

function parseWithSchema<TValue>(
  schema: z.ZodType<TValue>,
  payload: unknown,
  code: CoreErrorCode,
  message: string,
): Result<TValue> {
  const parsed = schema.safeParse(payload);
  if (!parsed.success) {
    return failure(code, message, issuesFromZod(parsed.error.issues));
  }

  return ok(parsed.data);
}

export function validateSourceRepositoryIndex(
  payload: unknown,
  options?: SourceRepositoryIndexValidationOptions,
): Result<SourceRepositoryIndex> {
  const parsed = parseWithSchema(
    SOURCE_REPOSITORY_INDEX_SCHEMA,
    payload,
    "SOURCE_REPOSITORY_INDEX_INVALID",
    "Invalid source repository index.",
  );
  if (!parsed.ok) {
    return parsed;
  }

  const issues: ValidationIssue[] = [];
  parsed.value.packages.forEach((entry, index) => {
    for (const [field, value] of [
      ["manifestUrl", entry.manifestUrl],
      ["packageUrl", entry.packageUrl],
    ] as const) {
      const issue = validateUrlValue(value, options?.urlPolicy);
      if (issue !== null) {
        issues.push({
          path: `$.packages[${index}].${field}`,
          message: issue.message,
        });
      }
    }
  });

  if (issues.length > 0) {
    return failure(
      "SOURCE_REPOSITORY_INDEX_INVALID",
      "Invalid source repository index.",
      issues,
    );
  }

  return parsed;
}

export function validateSourcePackageManifest(
  payload: unknown,
  options?: SourcePackageManifestValidationOptions,
): Result<SourcePackageManifest> {
  const parsed = parseWithSchema(
    SOURCE_PACKAGE_MANIFEST_SCHEMA,
    payload,
    "SOURCE_PACKAGE_MANIFEST_INVALID",
    "Invalid source package manifest.",
  );
  if (!parsed.ok) {
    return parsed;
  }

  const issues: ValidationIssue[] = [];
  const baseUrl = parsed.value.endpoints?.baseUrl;
  if (baseUrl !== undefined) {
    const issue = validateUrlValue(baseUrl, options?.urlPolicy);
    if (issue !== null) {
      issues.push({
        path: "$.endpoints.baseUrl",
        message: issue.message,
      });
    }
  }

  parsed.value.taxonomy?.mappingFiles.forEach((mappingFile, index) => {
    const issue = validateUrlValue(mappingFile, options?.urlPolicy);
    if (issue !== null) {
      issues.push({
        path: `$.taxonomy.mappingFiles[${index}]`,
        message: issue.message,
      });
    }
  });

  if (issues.length > 0) {
    return failure(
      "SOURCE_PACKAGE_MANIFEST_INVALID",
      "Invalid source package manifest.",
      issues,
    );
  }

  return parsed;
}

export function validateSourcePackageChecksums(
  payload: unknown,
): Result<SourcePackageChecksums> {
  const parsed = parseWithSchema(
    SOURCE_PACKAGE_CHECKSUMS_SCHEMA,
    payload,
    "SOURCE_PACKAGE_TAXONOMY_INVALID",
    "Invalid source package checksums.",
  );
  if (!parsed.ok) {
    return parsed;
  }

  const duplicates = collectDuplicateValues(parsed.value.files.map((entry) => entry.path));
  if (duplicates.length > 0) {
    return failure(
      "SOURCE_PACKAGE_TAXONOMY_INVALID",
      "Invalid source package checksums.",
      duplicates.map((path) => ({
        path: "$.files",
        message: `Duplicate checksum path: ${path}`,
      })),
    );
  }

  return parsed;
}

export function validateCanonicalTags(
  payload: unknown,
): Result<CanonicalTagsDocument> {
  const parsed = parseWithSchema(
    CANONICAL_TAGS_DOCUMENT_SCHEMA,
    payload,
    "TAG_TAXONOMY_INVALID",
    "Invalid canonical tag taxonomy.",
  );
  if (!parsed.ok) {
    return parsed;
  }

  const duplicates = collectDuplicateValues(parsed.value.tags.map((tag) => tag.canonicalKey));
  if (duplicates.length > 0) {
    return failure(
      "TAG_TAXONOMY_INVALID",
      "Invalid canonical tag taxonomy.",
      duplicates.map((canonicalKey) => ({
        path: "$.tags",
        message: `Duplicate canonicalKey: ${canonicalKey}`,
      })),
    );
  }

  return parsed;
}

export function validateLocalizedTagLabels(
  payload: unknown,
  options?: CanonicalKeyValidationOptions,
): Result<LocalizedTagLabelsDocument> {
  const parsed = parseWithSchema(
    LOCALIZED_TAG_LABELS_DOCUMENT_SCHEMA,
    payload,
    "TAG_TAXONOMY_INVALID",
    "Invalid localized tag labels.",
  );
  if (!parsed.ok) {
    return parsed;
  }

  const knownCanonicalKeys = normalizeKnownCanonicalKeys(options?.knownCanonicalKeys);
  if (knownCanonicalKeys === null) {
    return parsed;
  }

  const issues = Object.keys(parsed.value.labels)
    .filter((canonicalKey) => !knownCanonicalKeys.has(canonicalKey))
    .map((canonicalKey) => ({
      path: `$.labels.${canonicalKey}`,
      message: `Unknown canonicalKey: ${canonicalKey}`,
    }));

  if (issues.length > 0) {
    return failure(
      "TAG_TAXONOMY_INVALID",
      "Invalid localized tag labels.",
      issues,
    );
  }

  return parsed;
}

export function validateProviderTagMapping(
  payload: unknown,
  options?: ProviderTagMappingValidationOptions,
): Result<ProviderTagMappingDocument> {
  const parsed = parseWithSchema(
    PROVIDER_TAG_MAPPING_DOCUMENT_SCHEMA,
    payload,
    "TAG_MAPPING_INVALID",
    "Invalid provider tag mapping.",
  );
  if (!parsed.ok) {
    return parsed;
  }

  const issues: ValidationIssue[] = [];
  if (
    options?.expectedProviderKey !== undefined
    && parsed.value.providerKey !== options.expectedProviderKey
  ) {
    issues.push({
      path: "$.providerKey",
      message: `Expected providerKey ${options.expectedProviderKey}.`,
    });
  }

  const knownCanonicalKeys = normalizeKnownCanonicalKeys(options?.knownCanonicalKeys);
  if (knownCanonicalKeys !== null) {
    parsed.value.mappings.forEach((mapping, index) => {
      if (!knownCanonicalKeys.has(mapping.canonicalKey)) {
        issues.push({
          path: `$.mappings[${index}].canonicalKey`,
          message: `Unknown canonicalKey: ${mapping.canonicalKey}`,
        });
      }
    });
  }

  if (issues.length > 0) {
    return failure(
      "TAG_MAPPING_INVALID",
      "Invalid provider tag mapping.",
      issues,
    );
  }

  return parsed;
}
