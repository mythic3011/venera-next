export {
  createCoreRuntime,
  type CoreRuntime,
  type CreateCoreRuntimeOptions,
} from "./runtime/create-core-runtime.js";

export type {
  Comic,
  ComicMetadata,
  ComicTitle,
  CreateCanonicalComicInput,
  CreatedCanonicalComic,
} from "./domain/comic.js";
export type {
  Chapter,
  ChapterTreeNode,
} from "./domain/chapter.js";
export type {
  DiagnosticsEvent,
} from "./domain/diagnostics.js";
export type {
  ChapterId,
  ChapterSourceLinkId,
  ComicId,
  ComicTitleId,
  DiagnosticsEventId,
  PageId,
  ReaderSessionId,
  SourceLinkId,
  SourcePlatformId,
  StorageBackendId,
  StorageObjectId,
  StoragePlacementId,
} from "./domain/identifiers.js";
export type {
  Page,
  PageOrder,
  PageOrderItem,
  PageOrderWithItems,
} from "./domain/page.js";
export type {
  OpenReaderInput,
  OpenReaderResult,
  ReaderOpenTarget,
  ReaderSession,
  ReaderSessionPersistResult,
  ResolveReaderTargetInput,
  UpdateReaderPositionInput,
} from "./domain/reader.js";
export type {
  ChapterSourceLink,
  ProviderWorkRef,
  SourceLink,
  SourcePlatform,
} from "./domain/source.js";
export type {
  StorageObject,
  StoragePlacement,
} from "./domain/storage.js";
export {
  CORE_ERROR_CODES,
  CoreError,
  createCoreError,
  type CoreErrorCode,
} from "./shared/errors.js";
export {
  validateCanonicalTags,
  validateLocalizedTagLabels,
  validateProviderTagMapping,
  validateSourcePackageChecksums,
  validateSourcePackageManifest,
  validateSourceRepositoryIndex,
  type CanonicalKeyValidationOptions,
  type CanonicalTag,
  type CanonicalTagsDocument,
  type LocalizedTagLabelsDocument,
  type ProviderTagMappingDocument,
  type ProviderTagMappingValidationOptions,
  type SourceContractUrlPolicyOptions,
  type SourcePackageChecksums,
  type SourcePackageManifest,
  type SourcePackageManifestValidationOptions,
  type SourceRepositoryIndex,
  type SourceRepositoryIndexValidationOptions,
  type SourceRepositoryPackageEntry,
  type TagMappingConfidence,
  type TagNamespace,
  type TagValueType,
} from "./source-contracts/index.js";
export {
  err,
  isErr,
  isOk,
  ok,
  type Result,
} from "./shared/result.js";
export type {
  CoreRepositories,
  ComicMetadataRepositoryPort,
  ComicRepositoryPort,
  ComicTitleRepositoryPort,
  ChapterRepositoryPort,
  ChapterSourceLinkRepositoryPort,
  DiagnosticsEventRepositoryPort,
  PageOrderRepositoryPort,
  PageRepositoryPort,
  ReaderSessionRepositoryPort,
  SourceLinkRepositoryPort,
  SourcePlatformRepositoryPort,
  StorageObjectRepositoryPort,
  StoragePlacementRepositoryPort,
} from "./ports/repositories.js";
export type {
  CoreClockPort,
  CoreIdGeneratorPort,
  CoreTransactionPort,
} from "./ports/system.js";
