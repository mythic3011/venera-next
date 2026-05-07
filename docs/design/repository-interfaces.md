# Repository Interfaces Specification

**Language-agnostic repository (persistence) interface contracts.**

---

## Overview

Repositories provide abstraction over data storage. Each repository interface defines:
- Query operations (read-only)
- Command operations (write)
- Return types and error conditions
- Invariants and contracts

All repositories are **transactional** (operations either fully succeed or fully fail). Boundary enforcement keeps `src/domain`, `src/application`, and `src/ports` free of Kysely, SQLite, DB schema, and repository adapter imports.

All operations return a `Result`-shaped value: either a success value or a failure carrying a `CoreError`. Callers must not assume an exception-based protocol.

The `CoreRepositories` aggregate bundles all active ports under a single injectable object:

| Key | Port |
|-----|------|
| `comics` | ComicRepositoryPort |
| `comicMetadata` | ComicMetadataRepositoryPort |
| `comicTitles` | ComicTitleRepositoryPort |
| `chapters` | ChapterRepositoryPort |
| `pages` | PageRepositoryPort |
| `pageOrders` | PageOrderRepositoryPort |
| `readerSessions` | ReaderSessionRepositoryPort |
| `sourcePlatforms` | SourcePlatformRepositoryPort |
| `sourceLinks` | SourceLinkRepositoryPort |
| `chapterSourceLinks` | ChapterSourceLinkRepositoryPort |
| `storageObjects` | StorageObjectRepositoryPort |
| `storagePlacements` | StoragePlacementRepositoryPort |
| `diagnosticsEvents` | DiagnosticsEventRepositoryPort |
| `operationIdempotency` | OperationIdempotencyRepositoryPort |

---

## ComicRepositoryPort

Persistence layer for `Comic` entities.

### Queries

#### `getById(id) -> Comic | null | Error`

- Retrieves a comic by its `ComicId`.
- Returns `null` if the ID does not exist (not a hard error).

#### `listByNormalizedTitle(title) -> List<Comic> | Error`

- Returns all comics sharing the same `NormalizedTitle`.
- Returns an empty list if no match is found.
- Used for lookup and deduplication — not canonical identity.

### Commands

#### `create(input) -> Comic | Error`

- Creates a new `Comic` from `CreateComicInput`.
- Assigns a generated `ComicId`.
- Returns the created `Comic`.

---

## ComicMetadataRepositoryPort

Persistence layer for `ComicMetadata` entities (one-to-one with `Comic`).

### Queries

#### `getByComicId(comicId) -> ComicMetadata | null | Error`

- Retrieves metadata for the given `ComicId`.
- Returns `null` if no metadata record exists.

### Commands

#### `create(input) -> ComicMetadata | Error`

- Creates a new metadata record from `CreateComicMetadataInput`.
- Returns the created `ComicMetadata`.

#### `update(input) -> ComicMetadata | Error`

- Replaces the metadata fields from `CreateComicMetadataInput`.
- Returns the updated `ComicMetadata`.

---

## ComicTitleRepositoryPort

Persistence layer for `ComicTitle` entities (many-to-one with `Comic`).

### Queries

#### `listByComic(comicId) -> List<ComicTitle> | Error`

- Returns all title records associated with the given `ComicId`.
- Returns an empty list if none exist.

### Commands

#### `addTitle(input) -> ComicTitle | Error`

- Adds a title entry from `AddComicTitleInput`.
- Returns the created `ComicTitle`.

#### `removeTitle(id) -> void | Error`

- Removes the title entry identified by `ComicTitleId`.
- No return value on success.

---

## ChapterRepositoryPort

Persistence layer for `Chapter` entities.

Note: `chapterNumber` is ordering metadata, not an identity field. There is no `getChapterByNumber` or `findChaptersByNumber` method — lookup by chapter number is not a supported repository operation.

### Queries

#### `getById(id) -> Chapter | null | Error`

- Retrieves a chapter by its `ChapterId`.
- Returns `null` if the ID does not exist.

#### `listTreeByComic(comicId) -> List<ChapterTreeNode> | Error`

- Returns the hierarchical chapter tree for the given `ComicId`.
- Each node is a `ChapterTreeNode` carrying its children.
- Returns an empty list if no chapters exist.

#### `listChildren(input) -> List<Chapter> | Error`

- Returns the direct children of a parent chapter node, using `ListChapterChildrenInput`.
- Returns an empty list if no children exist.

#### `listByComic(comicId) -> List<Chapter> | Error`

- Returns all chapters for the given `ComicId` as a flat list.
- Returns an empty list if no chapters exist.

---

## PageRepositoryPort

Persistence layer for `Page` entities.

### Queries

#### `getById(id) -> Page | null | Error`

- Retrieves a page by its `PageId`.
- Returns `null` if the ID does not exist.

#### `listByChapter(chapterId) -> List<Page> | Error`

- Returns all pages for the given `ChapterId`, ordered by `page_index` ascending (0-based).
- Returns an empty list if no pages exist.

---

## PageOrderRepositoryPort

Persistence layer for per-chapter page ordering policy.

### Queries

#### `getActiveOrder(chapterId) -> PageOrderWithItems | null | Error`

- Returns the currently active page order for the given `ChapterId`, including the ordered page list.
- Returns `null` if no order record exists (caller should treat source order as default).

### Commands

#### `setUserOrder(input) -> PageOrderWithItems | Error`

- Persists a user-defined page order from `SetUserPageOrderInput`.
- `SetUserPageOrderInput` carries the `ChapterId` and the desired sequence of `PageId` values.
- Sets `order_type` to `user_override`.
- Returns the resulting `PageOrderWithItems`.

#### `resetToSourceOrder(chapterId) -> PageOrderWithItems | Error`

- Resets the chapter's order to the source-provided sequence.
- Sets `order_type` to `source`.
- Returns the resulting `PageOrderWithItems`.

---

## ReaderSessionRepositoryPort

Persistence layer for `ReaderSession` entities (one-to-one with `Comic`).

### Queries

#### `getByComic(comicId) -> ReaderSession | null | Error`

- Returns the reader session for the given `ComicId`.
- Returns `null` if no session has been created yet.
- No write side effects in the query path.

### Commands

#### `upsertPosition(input) -> ReaderSessionPersistResult | Error`

- Creates or updates the reader position from `UpdateReaderPositionInput`.
- `UpdateReaderPositionInput` carries: `comicId`, `chapterId`, `pageIndex`, and optionally `pageId`.
- Position authority is `chapterId` + `pageIndex`. The optional `pageId` field is advisory evidence/cache: if present and it does not match the page at `chapter_id` + `page_index`, the write still persists using `chapterId` + `pageIndex` as the canonical locator. Callers must not treat `pageId` as authoritative for position resolution.
- Last-write-wins semantics; no locking.
- Returns a `ReaderSessionPersistResult` describing what was created or updated.

#### `clear(comicId) -> void | Error`

- Removes the stored reader session for the given `ComicId`.
- Reset-target policy (e.g. first chapter/first page) is use-case-owned, not repository-owned.
- No return value on success.

---

## SourcePlatformRepositoryPort

Persistence layer for `SourcePlatform` entities.

Status lifecycle: `active` → `disabled` (reversible); `active` or `disabled` → `deprecated` (terminal). A platform in `deprecated` status cannot transition to `active` or `disabled`; any such attempt must return a `ValidationError`. Callers must enforce this at the use-case layer via `updateStatus`.

### Queries

#### `getById(id) -> SourcePlatform | null | Error`

- Retrieves a platform by its `SourcePlatformId`.
- Returns `null` if the ID does not exist.

#### `getByKey(canonicalKey) -> SourcePlatform | null | Error`

- Retrieves a platform by its canonical key string (e.g. `"copymanga"`).
- Returns `null` if the key does not exist.

#### `listByStatus(status) -> List<SourcePlatform> | Error`

- Returns all platforms whose current `SourcePlatformStatus` matches the given value.
- Valid status values: `active`, `disabled`, `deprecated`.
- Returns an empty list if no platforms match.
- This is the sole listing method. There is no `listEnabledSourcePlatforms` or `listAllSourcePlatforms` shorthand — callers pass the desired status explicitly.

### Commands

#### `updateStatus(input) -> SourcePlatform | Error`

- Updates the status of the platform identified by `SourcePlatformId`.
- `input` carries `id` and the new `status`.
- **Status transition enforcement**: transitions out of `deprecated` are rejected. Attempting to set `deprecated → active` or `deprecated → disabled` returns a `ValidationError`. The `deprecated` status is terminal.
- Returns the updated `SourcePlatform`.

---

## SourceLinkRepositoryPort

Persistence layer for `SourceLink` entities (links a `Comic` to a provider work on a `SourcePlatform`).

### Queries

#### `getById(id) -> SourceLink | null | Error`

- Retrieves a source link by its `SourceLinkId`.
- Returns `null` if the ID does not exist.

#### `listByComic(comicId) -> List<SourceLink> | Error`

- Returns all source links associated with the given `ComicId`.
- Returns an empty list if none exist.

#### `findByProviderWork(input) -> SourceLink | null | Error`

- Looks up a source link by `ProviderWorkRef` (a provider-scoped external work identifier).
- Returns `null` if no matching link exists.
- Used for deduplication during sync/import flows.

---

## ChapterSourceLinkRepositoryPort

Persistence layer for `ChapterSourceLink` entities (associates a `Chapter` with a `SourceLink`).

### Queries

#### `listByChapter(chapterId) -> List<ChapterSourceLink> | Error`

- Returns all source link associations for the given `ChapterId`.
- Returns an empty list if none exist.

#### `listBySourceLink(sourceLinkId) -> List<ChapterSourceLink> | Error`

- Returns all chapter associations for the given `SourceLinkId`.
- Returns an empty list if none exist.

---

## StorageObjectRepositoryPort

Persistence layer for `StorageObject` entities (content-addressable storage records).

### Queries

#### `getObject(id) -> StorageObject | null | Error`

- Retrieves a storage object by its `StorageObjectId`.
- Returns `null` if the ID does not exist.

---

## StoragePlacementRepositoryPort

Persistence layer for `StoragePlacement` entities (physical location records for a `StorageObject`).

### Queries

#### `listPlacements(storageObjectId) -> List<StoragePlacement> | Error`

- Returns all placement records for the given `StorageObjectId`.
- A storage object may have zero or more placements (e.g. cached in multiple locations).
- Returns an empty list if no placements exist.

---

## DiagnosticsEventRepositoryPort

Persistence layer for `DiagnosticsEvent` records (structured runtime telemetry).

### Commands

#### `record(input) -> DiagnosticsEvent | Error`

- Persists a new diagnostics event from `RecordDiagnosticsEventInput`.
- Returns the created `DiagnosticsEvent`.

### Queries

#### `query(input) -> List<DiagnosticsEvent> | Error`

- Returns diagnostics events matching the `DiagnosticsQuery` filter.
- Returns an empty list if no events match.

---

## OperationIdempotencyRepositoryPort

Persistence layer for `OperationIdempotencyRecord` entries used to deduplicate and resume operations.

### Queries

#### `get(input) -> OperationIdempotencyRecord | null | Error`

- Looks up an idempotency record by `GetOperationIdempotencyInput` (typically an operation key and input hash).
- Returns `null` if no record exists for the given key.

### Commands

#### `createInProgress(input) -> OperationIdempotencyRecord | Error`

- Creates a new idempotency record in the `in_progress` state from `CreateOperationIdempotencyInput`.
- Returns an `IdempotencyConflictError` if a record with the same key already exists.
- Returns the created `OperationIdempotencyRecord`.

#### `markCompleted(input) -> OperationIdempotencyRecord | Error`

- Transitions the record identified by `CompleteOperationIdempotencyInput` to the `completed` state, storing the result payload.
- Returns the updated `OperationIdempotencyRecord`.

---

## ImportBatchRepository (Deferred)

Import provenance handling is adapter-owned. No canonical `runtime/core` repository port for import batch persistence is committed in the current core slice. This section is retained as a placeholder only; implementation details are not authoritative here.

---

## Error Codes (Standard)

Repository ports in `runtime/core` return `Result<T, CoreError>`-shaped failures.

Names below are conceptual error categories, not required thrown exception classes:

| Error | Meaning | HTTP Equivalent |
|-------|---------|-----------------|
| `NotFoundError` | Entity or relation not found | 404 |
| `DuplicateError` | Constraint violated (unique, etc.) | 409 |
| `ValidationError` | Data invalid (type, range, status transition) | 422 |
| `ForbiddenError` | Operation denied by policy/permissions | 403 |
| `IdempotencyConflictError` | Same idempotency key with different input hash | 409 |
| `ConstraintError` | Foreign key or check constraint | 422 |
| `TransactionError` | Atomic operation failed | 500 |
| `StorageError` | Database unavailable | 503 |

---

## Transaction Guarantees

**All repository operations guarantee**:
- **Atomicity**: Operation fully succeeds or fully fails (no partial state)
- **Consistency**: Database invariants maintained (FK, unique, check constraints)
- **Isolation**: Concurrent operations do not see partial results
- **Durability**: Successful operations are persisted (committed)

**Deadlock handling**:
- Repository implementations must return deterministic `TransactionError` / `StorageError` outcomes for lock contention and busy-state failures.
- Retry/backoff policy is orchestration/infrastructure policy and is not mandated by this contract.

---

## Batch Operations

**Status**: Planned/Deferred unless explicitly implemented by the active core slice.

When implemented, batch operations must be atomic: all succeed or all fail.
