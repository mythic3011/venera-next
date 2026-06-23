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

Repository ports are intended to stay above DB dialects and are not the adapter insertion seam. That boundary goal is not the same thing as a proven claim that the current SQLite implementation is backend-portable. The live runtime still contains SQLite-specific infrastructure, DDL, seed, and migration semantics that must be audited before any non-SQLite backend is approved. Any dialect branching must stay beneath these ports; if backend work requires changing `src/domain`, `src/application`, or `src/ports`, the boundary decision must be reopened. Historical V1 implementation-boundary authority lives in `docs/design/archive/v1/database-adapter-implementation-boundary.md`, while deployment-mode strategy lives in `docs/design/archive/v1/production-database-adapter-strategy.md`.

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
| `userCollections` | UserCollectionRepositoryPort |
| `userCollectionItems` | UserCollectionItemRepositoryPort |
| `sourcePlatforms` | SourcePlatformRepositoryPort |
| `sourceLinks` | SourceLinkRepositoryPort |
| `chapterSourceLinks` | ChapterSourceLinkRepositoryPort |
| `storageBackends` | StorageBackendRepositoryPort |
| `storageObjects` | StorageObjectRepositoryPort |
| `storagePlacements` | StoragePlacementRepositoryPort |
| `diagnosticsEvents` | DiagnosticsEventRepositoryPort |
| `operationIdempotency` | OperationIdempotencyRepositoryPort |

---

## Shared Input Shapes

### ProviderWorkRef

Provider-scoped external work identity used for SourceLink deduplication.

```
ProviderWorkRef {
  sourcePlatformId: SourcePlatformId
  remoteWorkId: String
}
```

`ProviderWorkRef` is provenance lookup input only. It must not become canonical Comic identity.

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

#### `list(input) -> PaginatedResult<Comic> | Error`

- Lists comics with pagination, sort, and library-status policy.
- Input carries `includeRemoved`, `libraryStatus`, `sortBy`, `sortOrder`, `limit`, and `offset`.
- Default browse behavior must exclude `libraryStatus = removed` unless `includeRemoved = true`.

#### `search(input) -> PaginatedResult<ComicSearchResult> | Error`

- Searches comics by normalized/title/metadata fields according to the active search implementation.
- Input carries `query`, `includeRemoved`, `limit`, and `offset`.
- Raw query logging is not part of this port; diagnostics must use sanitized/hash payloads.

### Commands

#### `create(input) -> Comic | Error`

- Creates a new `Comic` from `CreateComicInput`.
- Assigns a generated `ComicId`.
- Returns the created `Comic`.

#### `updateLibraryStatus(input) -> Comic | Error`

- Updates `Comic.libraryStatus` and `removedAt`.
- `libraryStatus = "removed"` preserves child rows, reader session state, source links, and collection membership.
- Hard delete/purge is a separate explicit operation and must not be hidden behind this method.
- Returns the updated `Comic`.

#### `delete(id) -> void | Error`

- Permanently deletes the Comic row and dependent rows through the configured cascade policy.
- This is the hard-purge operation for UC-004b only; normal library removal must use `updateLibraryStatus`.
- Implementation must not rely on undefined FK cascade ordering between ReaderSession and Chapter/Page paths; ReaderSession rows must be explicitly removed first or protected by deferred page-position constraints.
- Storage byte cleanup is not implied by this repository method.

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
- If cover fields are updated, rejects conflicting cover references where `coverPageId.storageObjectId` differs from `coverStorageObjectId`.
- If `coverStatus = "synced"`, caller/use-case must verify a readable authoritative placement exists before claiming synced cover availability.
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

#### `replacePrimaryTitle(input) -> ComicTitle | Error`

- Replaces the comic's primary title in the same transaction that updates `ComicMetadata.title`.
- Rejects changes that would leave a comic with zero primary title rows.
- Returns the new primary `ComicTitle`.

#### `removeTitle(id) -> void | Error`

- Removes the title entry identified by `ComicTitleId`.
- Rejects removal when the target is the comic's only primary title unless the same transaction also installs a replacement primary title and updates `ComicMetadata.title`.
- No return value on success.

---

## ChapterRepositoryPort

Persistence layer for `Chapter` entities.

Note: `chapterNumber` is ordering metadata, not an identity field. There is no `getChapterByNumber` or `findChaptersByNumber` method — lookup by chapter number is not a supported repository operation.
Hierarchy mutations must reject self-parenting, cycles, and nesting deeper than 8 nodes before commit.

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

### Commands

#### `create(input) -> Chapter | Error`

- Creates a Chapter with validated `comicId`, optional `parentChapterId`, `chapterKind`, `chapterNumber`, title, and display label.
- Rejects self-parenting, cross-comic parent references, cycles, and nesting deeper than 8 nodes.
- Returns the created Chapter.

#### `update(input) -> Chapter | Error`

- Updates mutable Chapter fields such as `parentChapterId`, `chapterKind`, `chapterNumber`, title, and display label.
- Hierarchy updates must enforce same-comic parent ownership, cycle rejection, and maximum depth.
- Returns the updated Chapter.

#### `delete(input) -> void | Error`

- Deletes a Chapter and dependent Pages/PageOrders/ChapterSourceLinks according to cascade policy.
- Input must choose an explicit child-handling mode: `delete_subtree`, `reparent_children`, or `reject_if_children`.
- Implementations must not silently set child `parentChapterId` to null.
- This is a structural delete, not a library removal shortcut.

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

### Commands

#### `create(input) -> Page | Error`

- Creates one Page with validated parent Chapter, 0-based `pageIndex`, optional StorageObject reference, optional ChapterSourceLink provenance, and image metadata.
- Enforces `(chapterId, pageIndex)` uniqueness.
- Returns the created Page.

#### `createMany(input) -> List<Page> | Error`

- Creates multiple Pages for one Chapter atomically.
- Enforces all page-index, storage-object, and chapter-source-link constraints before commit.
- Returns created Pages in `pageIndex` order.

#### `update(input) -> Page | Error`

- Updates mutable Page fields such as `storageObjectId`, `chapterSourceLinkId`, MIME type, dimensions, and checksum.
- `chapterId` and `pageIndex` remain immutable unless a future explicit page-reindex contract is approved.
- Returns the updated Page.

---

## PageOrderRepositoryPort

Persistence layer for per-chapter page ordering policy.

### Queries

#### `getActiveOrder(chapterId) -> PageOrderWithItems | null | Error`

- Returns the page order with `status = "active"` for the given `ChapterId`, including the ordered page list.
- Returns `null` if no order record exists (caller should treat source order as default).

### Commands

#### `setUserOrder(input) -> PageOrderWithItems | Error`

- Persists a user-defined page order from `SetUserPageOrderInput`.
- `SetUserPageOrderInput` carries the `ChapterId` and the desired sequence of `PageId` values.
- Persists `order_type = 'user_override'` and `status = 'active'`; any previously active order for the chapter must transition to `superseded` or `inactive`.
- Returns the resulting `PageOrderWithItems`.

#### `resetToSourceOrder(chapterId) -> PageOrderWithItems | Error`

- Rebuilds the active order from the chapter's current canonical page sequence (`page_index` ascending).
- The resulting active row uses `order_type = 'source'` if materialized. Implementations may also return a synthetic source order when no persisted active order exists.
- Returns the resulting `PageOrderWithItems`.

---

## ReaderSessionRepositoryPort

Persistence layer for `ReaderSession` lifecycle rows. A comic may have multiple non-active historical rows, but at most one active row.

### Queries

#### `getActiveByComic(comicId) -> ReaderSession | null | Error`

- Returns the active reader session for the given `ComicId`.
- Returns `null` if no active session exists.
- No write side effects in the query path.

#### `listByComic(comicId) -> List<ReaderSession> | Error`

- Returns reader session lifecycle rows for the given `ComicId`.
- Used for diagnostics/history only; normal resume logic uses `getActiveByComic`.

### Commands

#### `upsertPosition(input) -> ReaderSessionPersistResult | Error`

- Creates or updates the active reader position from `UpdateReaderPositionInput`.
- `UpdateReaderPositionInput` carries: `comicId`, `pageId`, optional `sourceLinkId`, and optional `sessionState` (default `active`).
- Position authority is `pageId`; `chapterId` and `pageIndex` are derived from the referenced Page.
- The write is rejected with `READER_INVALID_POSITION` if `pageId` does not exist, the Page's Chapter does not belong to the supplied `comicId`, or `sourceLinkId` is supplied but belongs to a different Comic.
- `sourceLinkId` is read-context evidence only and must not override canonical page position.
- If creating a new active row while an active row already exists, the repository must update the existing active row or fail on the at-most-one-active constraint; it must not create two active rows.
- Current persistence semantics are last-write-wins within the local single-runtime model; there is no multi-device conflict protocol.
- Returns a `ReaderSessionPersistResult` describing what was created or updated.

#### `abandonActive(comicId) -> ReaderSession | null | Error`

- Marks the active reader session for the given `ComicId` as `sessionState = "abandoned"`.
- Returns the abandoned ReaderSession, or `null` if no active session existed.
- Does not hard-delete the lifecycle row.

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

#### `create(input) -> SourcePlatform | Error`

- Creates a source platform catalog entry with unique immutable `canonicalKey`.
- Rejects unsupported `kind` or duplicate canonical key.
- Returns the created SourcePlatform.

#### `updateStatus(input) -> SourcePlatform | Error`

- Updates the status of the platform identified by `SourcePlatformId`.
- `input` carries `id` and the new `status`.
- **Status transition enforcement**: transitions out of `deprecated` are rejected. Attempting to set `deprecated → active` or `deprecated → disabled` returns a `ValidationError`. The `deprecated` status is terminal.
- Returns the updated `SourcePlatform`.

Kind semantics:
- `local` and `remote` are content-bearing platform kinds and may contribute to `Comic.originHint`.
- `virtual` is internal synthesized/projection authority only; it must not be used for user-defined collections.

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

### Commands

#### `create(input) -> SourceLink | Error`

- Creates a SourceLink for a Comic and SourcePlatform.
- Enforces `(sourcePlatformId, remoteWorkId)` uniqueness through the DB constraint.
- Does not by itself recompute `Comic.originHint`; source-link use cases must perform that update in the same transaction.
- Returns the created SourceLink.

#### `update(input) -> SourceLink | Error`

- Updates mutable SourceLink fields such as `remoteUrl`, `displayTitle`, `linkStatus`, and `confidence`.
- Rejects changing `sourcePlatformId` or `remoteWorkId` in a way that violates provider-work uniqueness.
- Returns the updated SourceLink.

#### `updateStatus(input) -> SourceLink | Error`

- Updates SourceLink `linkStatus` and optional `confidence`.
- Caller/use-case must recompute `Comic.originHint` in the same transaction when active membership changes.
- Returns the updated SourceLink.

#### `delete(id) -> void | Error`

- Deletes a SourceLink and dependent ChapterSourceLinks according to cascade policy.
- Caller/use-case must recompute `Comic.originHint` in the same transaction.

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

#### `getAggregatedSourceOrder(chapterId) -> Integer | null | Error`

- Returns `MIN(sourceOrder)` across active ChapterSourceLinks for the Chapter whose parent SourceLink and SourcePlatform are also active.
- Returns `null` when no qualifying active source-order evidence exists.
- Used by first-canonical-chapter target resolution.

#### `listAggregatedSourceOrderByComic(comicId) -> Map<ChapterId, Integer | null> | Error`

- Returns aggregated source-order evidence for all Chapters in a Comic.
- Avoids N+1 lookups during ResolveReaderTarget fallback sorting.

### Commands

#### `upsert(input) -> ChapterSourceLink | Error`

- Creates or updates a ChapterSourceLink keyed by `(sourceLinkId, remoteChapterId)`.
- Validates that Chapter and SourceLink belong to the same Comic.
- Persists optional `sourceOrder` as source ordering evidence.
- Returns the created or updated ChapterSourceLink.

#### `updateStatus(input) -> ChapterSourceLink | Error`

- Updates `linkStatus` and optional `confidence` for a ChapterSourceLink.
- Returns the updated ChapterSourceLink.

#### `delete(id) -> void | Error`

- Deletes a ChapterSourceLink.
- Does not delete the canonical Chapter or parent SourceLink.

---

## StorageBackendRepositoryPort

Persistence layer for configured `StorageBackend` entries.

### Queries

#### `getById(id) -> StorageBackend | null | Error`

- Retrieves a storage backend by `StorageBackendId`.
- Returns `null` if the ID does not exist.

#### `getByKey(backendKey) -> StorageBackend | null | Error`

- Retrieves a storage backend by stable backend key.
- Returns `null` if no backend exists for the key.

#### `listByStatus(status) -> List<StorageBackend> | Error`

- Returns all backends with the requested lifecycle status.
- Returns an empty list if none exist.

### Commands

#### `create(input) -> StorageBackend | Error`

- Creates a backend with unique `backendKey`, supported `backendKind`, validated `configJson`, positive `configSchemaVersion`, optional `secretRef`, and lifecycle status.
- Rejects plaintext secrets embedded in `configJson`.
- Returns the created StorageBackend.

#### `updateConfig(input) -> StorageBackend | Error`

- Updates backend display/config fields.
- Must validate `configSchemaVersion` and reject unsupported versions fail-closed.
- Must keep credentials outside `configJson`; `secretRef` is the only credential pointer.
- Returns the updated StorageBackend.

#### `updateStatus(input) -> StorageBackend | Error`

- Updates backend lifecycle status.
- Deprecated status is terminal unless a future storage-backend lifecycle contract changes it.
- Returns the updated StorageBackend.

---

## StorageObjectRepositoryPort

Persistence layer for `StorageObject` entities (logical storage object records).

### Queries

#### `getObject(id) -> StorageObject | null | Error`

- Retrieves a storage object by its `StorageObjectId`.
- Returns `null` if the ID does not exist.

### Commands

#### `create(input) -> StorageObject | Error`

- Creates a logical storage object metadata row.
- Object existence does not prove readable bytes; readable placement resolution remains required.
- Returns the created StorageObject.

#### `updateMetadata(input) -> StorageObject | Error`

- Updates content hash, size, MIME type, and updated timestamp after materialization or verification.
- Returns the updated StorageObject.

---

## StoragePlacementRepositoryPort

Persistence layer for `StoragePlacement` entities (physical location records for a `StorageObject`).

### Queries

#### `listPlacements(storageObjectId) -> List<StoragePlacement> | Error`

- Returns all placement records for the given `StorageObjectId`.
- A storage object may have zero or more placements (e.g. cached in multiple locations).
- Returns an empty list if no placements exist.

#### `resolveReadablePlacement(storageObjectId) -> StoragePlacement | null | Error`

- Returns the preferred readable placement for the storage object according to role/status policy.
- Returns `null` when the object exists but has no readable placement; callers must surface `STORAGE_OBJECT_UNAVAILABLE` or a placeholder/retry state.
- Does not mutate placement state.

### Commands

#### `create(input) -> StoragePlacement | Error`

- Creates a placement for a StorageObject on a StorageBackend.
- Enforces `(storageObjectId, storageBackendId, objectKey)` uniqueness and at-most-one authority placement.
- Returns the created StoragePlacement.

#### `updateSyncStatus(input) -> StoragePlacement | Error`

- Updates placement `syncStatus`, optional verification timestamp, and updated timestamp.
- Used for transitions such as `pending -> uploading -> synced`, `uploading -> failed`, or `synced -> evicted`.
- Returns the updated StoragePlacement.

#### `delete(id) -> void | Error`

- Deletes a placement record.
- Does not delete the logical StorageObject row.

---

## UserCollectionRepositoryPort

Persistence layer for `UserCollection` entities.

### Queries

#### `getById(id) -> UserCollection | null | Error`

- Retrieves a collection by `UserCollectionId`.
- Returns `null` if the ID does not exist.

#### `list(input) -> List<UserCollection> | Error`

- Lists user collections using caller-provided pagination/sort policy.
- Returns an empty list if no collections exist.

### Commands

#### `create(input) -> UserCollection | Error`

- Creates a collection with validated display name, optional description, optional cover, and sort order.
- Returns the created collection.

#### `update(input) -> UserCollection | Error`

- Updates mutable collection metadata.
- Cover storage object references must follow the storage availability policy before UI claims readable bytes.
- Returns the updated collection.

#### `delete(id) -> void | Error`

- Deletes the collection and cascades only UserCollectionItem membership rows.
- Does not delete Comics.

---

## UserCollectionItemRepositoryPort

Persistence layer for `UserCollectionItem` membership and manual ordering.

### Queries

#### `listByCollection(input) -> List<UserCollectionItemWithComic> | Error`

- Lists collection items joined with Comics.
- Applies `includeRemoved` policy at the use-case layer or via input.
- Supports pagination.

### Commands

#### `addComic(input) -> UserCollectionItem | Error`

- Adds a Comic to a collection.
- Enforces `(collectionId, comicId)` uniqueness.
- Assigns or shifts `sortIndex` atomically for manual order.

#### `removeComic(input) -> void | Error`

- Removes a Comic from a collection.
- Does not delete the Comic or reader progress.

#### `replaceManualOrder(input) -> List<UserCollectionItem> | Error`

- Replaces manual order by updating all affected `sortIndex` values in one transaction.
- Rejects incomplete, duplicated, or unknown membership lists.

#### `moveComic(input) -> List<UserCollectionItem> | Error`

- Moves one collection item before/after another item without requiring a full `orderedComicIds` replacement payload.
- Validates both comic IDs belong to the same collection, when an anchor item is supplied.
- Reassigns affected `sortIndex` values atomically.
- Returns the updated ordered item list or the affected window, depending on adapter needs.

---

## DiagnosticsEventRepositoryPort

Persistence layer for `DiagnosticsEvent` records (structured runtime telemetry).

### Commands

#### `record(input) -> DiagnosticsEvent | Error`

- Persists a new diagnostics event from `RecordDiagnosticsEventInput`.
- Returns the created `DiagnosticsEvent` when successful.
- This command is best-effort from the perspective of business use cases: diagnostics write failure must not cause the primary use case transaction to fail or roll back.
- Implementations may surface diagnostics persistence failure to local debug logs/metrics, but callers must not propagate it as the use-case result unless the use case is explicitly querying diagnostics.

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
- Returns an `IdempotencyConflictError` if a record with the same key already exists and cannot be reclaimed under the TTL policy.
- Returns the created `OperationIdempotencyRecord`.

#### `claimOrReplay(input) -> IdempotencyClaimResult | Error`

- Atomically evaluates an idempotency key and returns one of: `claimed_new`, `replay_completed`, `conflict_different_input`, `blocked_in_progress`, `blocked_failed_retry_window`, or `claimed_stale_same_input`.
- Applies the operation lease TTL for stale `in_progress` records and retry TTL for failed records.
- Must be used by mutation use cases that need liveness after process crash.

#### `renewLease(input) -> OperationIdempotencyRecord | Error`

- Refreshes `updatedAt` for an owned `in_progress` operation before its lease expires.
- Used only by long-running operations.

#### `markCompleted(input) -> OperationIdempotencyRecord | Error`

- Transitions the record identified by `CompleteOperationIdempotencyInput` to the `completed` state, storing the result payload.
- Returns the updated `OperationIdempotencyRecord`.

#### `markFailed(input) -> OperationIdempotencyRecord | Error`

- Transitions an `in_progress` idempotency record to `failed`.
- Failed records are not replayable as success; same-input retry is allowed only after the retry TTL.
- Returns the updated `OperationIdempotencyRecord`.

#### `cleanupExpired(input) -> CleanupSummary | Error`

- Removes stale failed records and stale unclaimed in-progress records after their retention window.
- Must not remove completed replay records before their replay retention expires.

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
