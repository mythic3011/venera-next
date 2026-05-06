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

---

## ComicRepository

Persistence layer for Comic and ComicMetadata entities.

### Queries

#### `getComicById(id: ComicId) -> Comic | Error`
**Contract**:
- Retrieves a comic by ID
- Returns Comic with all metadata
- Throws: `NotFoundError` if ID not in database

#### `listByNormalizedTitle(normalizedTitle: NormalizedTitle) -> List<Comic> | Error`
**Contract**:
- Retrieves all comics sharing the same normalized title
- Returns domain-shaped comics with all metadata
- Returns empty list if the title is not found
- Used for lookup only, not canonical identity

#### `listAllComics(limit: Integer = 1000, offset: Integer = 0) -> List<Comic> | Error`
**Contract**:
- Returns paginated list of all comics
- Default page size 1000
- Ordered by `created_at` ascending
- Returns empty list if no comics

#### `searchComics(query: String, limit: Integer = 100) -> List<Comic> | Error`
**Contract**:
- Full-text search on `title`, `description`, and `author`
- Case-insensitive
- Ordered by relevance
- Returns up to `limit` results
- Returns empty list if no matches

### Commands

#### `createComic(title: String, description: String = null) -> Comic | Error`
**Contract**:
- Creates new Comic with ComicMetadata
- Generates UUID for ID
- Normalizes title for `normalized_title`
- Returns created Comic with ID assigned
- Atomic: both Comic and ComicMetadata inserted or both fail

Idempotent mutation replay is a separate persistence concern. Stored `result_json` must be treated as a public DTO projection and validated strictly before replay reaches the application layer.

#### `updateComicMetadata(id: ComicId, metadata: ComicMetadata) -> Comic | Error`
**Contract**:
- Updates only metadata (title, description, cover, etc.)
- Throws: `NotFoundError` if ID not found
- Returns updated Comic

#### `deleteComic(id: ComicId) -> Boolean | Error`
**Contract**:
- Deletes comic and all related data (cascading)
- Throws: `NotFoundError` if ID not found
- Returns true on success
- Atomic: all related chapters, pages, favorites deleted together

---

## ChapterRepository

Persistence layer for Chapter entities.

### Queries

#### `getChapterById(id: ChapterId) -> Chapter | Error`
**Contract**:
- Retrieves chapter by ID
- Returns Chapter with all metadata
- Throws: `NotFoundError` if ID not found

#### `listChaptersByComic(comicId: ComicId, limit: Integer = 1000) -> List<Chapter> | Error`
**Contract**:
- Returns all chapters for a comic
- Ordered by `chapter_number` ascending
- Returns empty list if no chapters
- Throws: `NotFoundError` if comic ID not found

#### `findChaptersByNumber(comicId: ComicId, chapterNumber: Float) -> List<Chapter> | Error`
**Contract**:
- Lookup helper for ordering/matching only (chapterNumber is not identity authority)
- May return multiple chapters for the same `chapterNumber`
- Returns empty list if no matches

#### `getChapterCount(comicId: ComicId) -> Integer | Error`
**Contract**:
- Returns count of chapters in comic
- Throws: `NotFoundError` if comic not found

### Commands

#### `createChapter(comicId: ComicId, chapterNumber: Float, title: String = null) -> Chapter | Error`
**Contract**:
- Creates new chapter
- Generates UUID for ID
- Throws: `NotFoundError` if comic not found
- Throws: `ValidationError` if chapter_number <= 0
- Returns created Chapter with ID assigned

#### `updateChapter(id: ChapterId, chapterNumber: Float = null, title: String = null) -> Chapter | Error`
**Contract**:
- Updates chapter metadata
- If `chapterNumber` provided and different, re-orders within comic
- Throws: `NotFoundError` if ID not found
- Returns updated Chapter

#### `deleteChapter(id: ChapterId) -> Boolean | Error`
**Contract**:
- Deletes chapter and all pages
- Throws: `NotFoundError` if ID not found
- Returns true on success
- Atomic: all pages deleted with chapter

---

## PageRepository

Persistence layer for Page entities.

### Queries

#### `getPageById(id: PageId) -> Page | Error`
**Contract**:
- Retrieves page by ID
- Returns Page with all metadata
- Throws: `NotFoundError` if not found

#### `listPagesByChapter(chapterId: ChapterId) -> List<Page> | Error`
**Contract**:
- Returns all pages in chapter
- Ordered by `page_index` ascending (0-based)
- Ensures contiguous indices
- Returns empty list if no pages
- Throws: `NotFoundError` if chapter not found

#### `getPageByIndex(chapterId: ChapterId, pageIndex: Integer) -> Page | Error`
**Contract**:
- Retrieves page at specific index within chapter
- Throws: `NotFoundError` if chapter or page not found
- Throws: `ValidationError` if index < 0

#### `getPageCount(chapterId: ChapterId) -> Integer | Error`
**Contract**:
- Returns count of pages in chapter
- Throws: `NotFoundError` if chapter not found

### Commands

#### `createPage(chapterId: ChapterId, pageIndex: Integer, storageObjectId: StorageObjectId = null) -> Page | Error`
**Contract**:
- Creates new page at given index
- Automatically reindexes pages if necessary (shifts higher indices)
- Generates UUID for ID
- Stores page identity plus optional storage object reference only
- Must not expose raw filesystem/cache paths as canonical fields
- Throws: `NotFoundError` if chapter not found
- Throws: `ValidationError` if pageIndex < 0
- Returns created Page with ID assigned

#### `createPages(chapterId: ChapterId, pages: List<PageCreateRequest>) -> List<Page> | Error`
**Contract**:
- Batch create multiple pages
- Pages inserted with auto-incrementing indices
- Throws: `NotFoundError` if chapter not found
- Returns list of created Pages
- Atomic: all pages inserted or all fail

#### `updatePage(id: PageId, storageObjectId: StorageObjectId = null) -> Page | Error`
**Contract**:
- Updates page metadata (storage object reference, etc.)
- Must not expose raw filesystem/cache paths as canonical fields
- Throws: `NotFoundError` if not found
- Returns updated Page

#### `deletePage(id: PageId) -> Boolean | Error`
**Contract**:
- Deletes page and reindexes remaining pages
- Throws: `NotFoundError` if not found
- Returns true on success

#### `reindexPages(chapterId: ChapterId) -> List<Page> | Error`
**Contract**:
- Resets all page indices to be contiguous 0, 1, 2, ...
- Throws: `NotFoundError` if chapter not found
- Returns reindexed pages
- Used after imports or manual edits

---

## ReaderSessionRepository

Persistence layer for ReaderSession entities.

### Queries

#### `getReaderSession(comicId: ComicId) -> ReaderSession | Error`
**Contract**:
- Retrieves reader position for a comic
- No write side effects in query path
- Throws: `NotFoundError` if session not found
- Returns ReaderSession

#### `listReaderSessions(limit: Integer = 1000) -> List<ReaderSession> | Error`
**Contract**:
- Returns all reader sessions
- Ordered by `updated_at` descending
- Returns empty list if no sessions

### Commands

#### `updateReaderPosition(comicId: ComicId, chapterId: ChapterId, pageIndex: Integer) -> ReaderSession | Error`
**Contract**:
- Updates reader position
- Session creation/fallback policy is use-case-owned, not query-owned
- Throws: `NotFoundError` if comic not found
- Throws: `ValidationError` if chapter not in comic or page index invalid
- Returns updated ReaderSession
- Last-write-wins semantics (no locking)
- Atomic within reader-session persistence scope only

#### `clearReaderSession(comicId: ComicId) -> Boolean | Error`
**Contract**:
- Clears stored reader session state for the comic
- Reset target policy (for example first chapter/page) is use-case-owned, not repository-owned
- Throws: `NotFoundError` if comic not found
- Returns true on success

---

## PageOrderRepository

Persistence layer for PageOrder policy.

### Queries

#### `getPageOrder(chapterId: ChapterId) -> PageOrder | Error`
**Contract**:
- Retrieves page order policy for chapter
- No write side effects in query path
- Throws: `NotFoundError` if chapter has no stored PageOrder
- Returns PageOrder

#### `getPageOrderType(chapterId: ChapterId) -> String | Error`
**Contract**:
- Returns order type: 'source', 'user_override', 'import_detected'
- Throws: `NotFoundError` if chapter not found

### Commands

#### `setUserPageOrder(chapterId: ChapterId, pageIds: List<PageId>) -> PageOrder | Error`
**Contract**:
- Sets user-defined page order
- Validates all page IDs belong to chapter
- Updates `order_type` to 'user_override'
- Throws: `NotFoundError` if chapter not found
- Throws: `ValidationError` if page IDs don't match chapter
- Returns updated PageOrder

#### `resetPageOrder(chapterId: ChapterId) -> PageOrder | Error`
**Contract**:
- Resets to source order
- Updates `order_type` to 'source'
- Throws: `NotFoundError` if chapter not found
- Returns updated PageOrder

---

## SourcePlatformRepository

Persistence layer for SourcePlatform entities.

### Queries

#### `getSourcePlatformById(id: SourcePlatformId) -> SourcePlatform | Error`
**Contract**:
- Retrieves platform by ID
- Throws: `NotFoundError` if not found

#### `getSourcePlatformByKey(canonicalKey: String) -> SourcePlatform | Error`
**Contract**:
- Retrieves platform by canonical key (e.g., "copymanga")
- Throws: `NotFoundError` if not found
- Used for lookup during runtime

#### `listAllSourcePlatforms(includeDisabled: Boolean = false) -> List<SourcePlatform> | Error`
**Contract**:
- Returns all platforms
- If `includeDisabled` false, filters to `status = 'active'`
- Ordered by `display_name` ascending

#### `listEnabledSourcePlatforms() -> List<SourcePlatform> | Error`
**Contract**:
- Returns only active platforms (`status = 'active'`)
- Ordered by `display_name` ascending

### Commands

#### `createSourcePlatform(canonicalKey: String, displayName: String, kind: String) -> SourcePlatform | Error`
**Contract**:
- Creates new platform
- Generates UUID for ID
- Throws: `DuplicateError` if canonical_key already exists
- Throws: `ValidationError` if kind not in [local, remote, virtual]
- Returns created SourcePlatform

#### `updateSourcePlatform(id: SourcePlatformId, displayName: String = null, status: String = null) -> SourcePlatform | Error`
**Contract**:
- Updates platform metadata
- `status` must be one of `active | disabled | deprecated` when provided
- Throws: `NotFoundError` if not found
- Throws: `ValidationError` if status is invalid
- Returns updated SourcePlatform

#### `deleteSourcePlatform(id: SourcePlatformId) -> Boolean | Error`
**Contract**:
- Deletes platform (source links become null)
- Throws: `NotFoundError` if not found
- Returns true on success

---

## Source Package Contract Repositories (Deferred)

Repository/package manifest persistence is deferred until PackageStore implementation boundaries are finalized.

Current authority for this boundary is:

- Source-contract validators
- In-memory integrity verifier
- Source package artifact lifecycle contract
- Source package store contract

No canonical runtime/core repository port is committed here yet for installed package artifact storage.

---

## FavoriteRepository

Persistence layer for Favorite entities.

### Queries

#### `getFavorite(comicId: ComicId) -> Favorite | Error`
**Contract**:
- Retrieves favorite record
- Throws: `NotFoundError` if not favorited

#### `listFavorites(limit: Integer = 1000, offset: Integer = 0) -> List<Favorite> | Error`
**Contract**:
- Returns paginated list of favorites
- Ordered by `marked_at` descending by default in current core
- Returns empty list if none

#### `getFavoritesCount() -> Integer`
**Contract**:
- Returns count of favorited comics
- No error possible

#### `isFavorited(comicId: ComicId) -> Boolean`
**Contract**:
- Returns true if comic is favorited, false otherwise
- No error possible

### Commands

#### `markFavorite(comicId: ComicId) -> Favorite | Error`
**Contract**:
- Adds comic to favorites
- Throws: `NotFoundError` if comic not found
- If already favorited, returns existing favorite (idempotent)
- Returns Favorite

#### `unmarkFavorite(comicId: ComicId) -> Boolean | Error`
**Contract**:
- Removes comic from favorites
- Throws: `NotFoundError` if comic not found
- Returns true on success

#### `updateLastAccessed(comicId: ComicId) -> Favorite | Error`
**Contract**:
- Updates `last_accessed_at` timestamp
- Throws: `NotFoundError` if not favorited
- Returns updated Favorite

---

## ImportBatchRepository

**Status**: Deferred adapter/import boundary.

Import provenance handling is adapter-owned; this section is not current core canonical authority.

### Queries

#### `getImportBatchById(id: ImportBatchId) -> ImportBatch | Error`
**Contract**:
- Retrieves import batch
- Throws: `NotFoundError` if not found

#### `listActiveImportBatches() -> List<ImportBatch> | Error`
**Contract**:
- Returns batches where `completed_at` is null (in progress)
- Ordered by `created_at` ascending

#### `listCompletedImportBatches(limit: Integer = 100) -> List<ImportBatch> | Error`
**Contract**:
- Returns batches where `completed_at` is not null
- Ordered by `completed_at` descending
- Returns up to `limit` results

#### `getImportBatchBySource(sourceType: String, sourceRef: String) -> ImportBatch | Error`
**Contract**:
- Retrieves batch by import provenance descriptor (for adapter-owned idempotency checks)
- Throws: `NotFoundError` if not found

### Commands

#### `createImportBatch(sourceType: String, sourceRef: String, files: List<ImportFile>, metadata: Object) -> ImportBatch | Error`
**Contract**:
- Creates new import batch
- Generates UUID for ID
- Throws: `ValidationError` if sourceType invalid or files empty
- Throws: `DuplicateError` if same provenance descriptor already exists as active batch
- Returns created ImportBatch with `completed_at = null`

#### `completeImportBatch(id: ImportBatchId, comicId: ComicId = null) -> ImportBatch | Error`
**Contract**:
- Marks batch as completed
- Sets `completed_at = CURRENT_TIMESTAMP`
- Links to comic if `comicId` provided
- Throws: `NotFoundError` if batch not found
- Returns updated ImportBatch

#### `deleteImportBatch(id: ImportBatchId) -> Boolean | Error`
**Contract**:
- Deletes batch (does not delete linked comic)
- Throws: `NotFoundError` if not found
- Returns true on success

---

## Error Codes (Standard)

Repository ports in runtime/core return `Result<T, CoreError>`-shaped failures.

Names below are conceptual error categories, not required thrown exception classes:

| Error | Meaning | HTTP Equivalent |
|-------|---------|-----------------|
| `NotFoundError` | Entity or relation not found | 404 |
| `DuplicateError` | Constraint violated (unique, etc.) | 409 |
| `ValidationError` | Data invalid (type, range, etc.) | 422 |
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
- **Isolation**: Concurrent operations don't see partial results
- **Durability**: Successful operations persisted (committed)

**Deadlock handling**:
- Repository layer should return deterministic `TransactionError` / `StorageError` outcomes for lock contention and busy-state failures.
- Retry/backoff policy is orchestration/infrastructure policy and is not mandated by this contract slice.

---

## Batch Operations

**Status**: Planned/Deferred unless explicitly implemented by the active core slice.

Potential performance-oriented batch commands:

- `createPages(chapterId, pages)` - insert multiple pages
- `updateReaderPositions(sessions)` - bulk reader position updates
- `deletePages(pageIds)` - bulk delete with reindexing

When implemented, batch operations must be atomic: all succeed or all fail.
