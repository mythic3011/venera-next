# Repository Interfaces Specification

**Language-agnostic repository (persistence) interface contracts.**

---

## Overview

Repositories provide abstraction over data storage. Each repository interface defines:
- Query operations (read-only)
- Command operations (write)
- Return types and error conditions
- Invariants and contracts

All repositories are **transactional** (operations either fully succeed or fully fail).

---

## ComicRepository

Persistence layer for Comic and ComicMetadata entities.

### Queries

#### `getComicById(id: ComicId) -> Comic | Error`
**Contract**:
- Retrieves a comic by ID
- Returns Comic with all metadata
- Throws: `NotFoundError` if ID not in database

#### `getComicByNormalizedTitle(normalizedTitle: String) -> Comic | Error`
**Contract**:
- Retrieves comic by normalized title
- Returns Comic with all metadata
- Throws: `NotFoundError` if title not found
- Used for deduplication check

#### `listAllComics(limit: Integer = 1000, offset: Integer = 0) -> List<Comic> | Error`
**Contract**:
- Returns paginated list of all comics
- Default page size 1000
- Ordered by `created_at` ascending
- Returns empty list if no comics

#### `searchComics(query: String, limit: Integer = 100) -> List<Comic> | Error`
**Contract**:
- Full-text search on `title` and `description`
- Case-insensitive
- Ordered by relevance
- Returns up to `limit` results
- Returns empty list if no matches

#### `getFavoritesCount() -> Integer`
**Contract**:
- Returns count of favorited comics
- No error possible

### Commands

#### `createComic(title: String, description: String = null) -> Comic | Error`
**Contract**:
- Creates new Comic with ComicMetadata
- Generates UUID for ID
- Normalizes title for `normalized_title`
- Returns created Comic with ID assigned
- Throws: `DuplicateError` if normalized title already exists
- Atomic: both Comic and ComicMetadata inserted or both fail

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

#### `getChapterByNumber(comicId: ComicId, chapterNumber: Float) -> Chapter | Error`
**Contract**:
- Retrieves chapter by comic ID and chapter number
- Throws: `NotFoundError` if not found

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
- Throws: `DuplicateError` if chapter number already exists for comic
- Throws: `ValidationError` if chapter_number <= 0
- Returns created Chapter with ID assigned

#### `updateChapter(id: ChapterId, chapterNumber: Float = null, title: String = null) -> Chapter | Error`
**Contract**:
- Updates chapter metadata
- If `chapterNumber` provided and different, re-orders within comic
- Throws: `NotFoundError` if ID not found
- Throws: `DuplicateError` if new chapter number conflicts
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

#### `createPage(chapterId: ChapterId, pageIndex: Integer, localCachePath: String = null) -> Page | Error`
**Contract**:
- Creates new page at given index
- Automatically reindexes pages if necessary (shifts higher indices)
- Generates UUID for ID
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

#### `updatePage(id: PageId, localCachePath: String = null) -> Page | Error`
**Contract**:
- Updates page metadata (cache path, etc.)
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
- Creates default session (chapter 0, page 0) if not found
- Never throws `NotFoundError` (creates on demand)
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
- Creates session if not found
- Throws: `NotFoundError` if comic not found
- Throws: `ValidationError` if chapter not in comic or page index invalid
- Returns updated ReaderSession
- Last-write-wins semantics (no locking)
- Atomic: position update + favorite timestamp update (if favorited)

#### `clearReaderSession(comicId: ComicId) -> Boolean | Error`
**Contract**:
- Resets reader position to start (chapter 0, page 0)
- Throws: `NotFoundError` if comic not found
- Returns true on success

---

## PageOrderRepository

Persistence layer for PageOrder policy.

### Queries

#### `getPageOrder(chapterId: ChapterId) -> PageOrder | Error`
**Contract**:
- Retrieves page order policy for chapter
- Creates default (source order) if not found
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
- If `includeDisabled` false, filters to `is_enabled = true`
- Ordered by `display_name` ascending

#### `listEnabledSourcePlatforms() -> List<SourcePlatform> | Error`
**Contract**:
- Returns only enabled platforms
- Ordered by `display_name` ascending

### Commands

#### `createSourcePlatform(canonicalKey: String, displayName: String, kind: String) -> SourcePlatform | Error`
**Contract**:
- Creates new platform
- Generates UUID for ID
- Throws: `DuplicateError` if canonical_key already exists
- Throws: `ValidationError` if kind not in [local, remote, virtual]
- Returns created SourcePlatform

#### `updateSourcePlatform(id: SourcePlatformId, displayName: String = null, isEnabled: Boolean = null) -> SourcePlatform | Error`
**Contract**:
- Updates platform metadata
- Throws: `NotFoundError` if not found
- Returns updated SourcePlatform

#### `deleteSourcePlatform(id: SourcePlatformId) -> Boolean | Error`
**Contract**:
- Deletes platform (source links become null)
- Throws: `NotFoundError` if not found
- Returns true on success

---

## SourceManifestRepository

Persistence layer for SourceManifest entities.

### Queries

#### `getManifestById(id: String) -> SourceManifest | Error`
**Contract**:
- Retrieves manifest by deterministic ID (hash)
- Throws: `NotFoundError` if not found
- Manifest is immutable once stored

#### `getManifestByPlatform(sourcePlatformId: SourcePlatformId) -> SourceManifest | Error`
**Contract**:
- Retrieves latest manifest for a platform
- Throws: `NotFoundError` if platform or manifest not found

#### `listManifestsByPlatform(sourcePlatformId: SourcePlatformId) -> List<SourceManifest> | Error`
**Contract**:
- Returns all manifests for a platform (versions)
- Ordered by `created_at` descending
- Returns empty list if none

### Commands

#### `createManifest(sourcePlatformId: SourcePlatformId, manifest: Object) -> SourceManifest | Error`
**Contract**:
- Creates new manifest (version)
- Validates against `schemas/source_manifest.schema.json`
- Computes deterministic ID (hash of content)
- Throws: `NotFoundError` if platform not found
- Throws: `ValidationError` if manifest invalid
- Returns created SourceManifest
- Idempotent: same manifest content = same ID (deduplicates)

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
- Ordered by `last_accessed_at` descending (most recent first)
- Returns empty list if none

#### `isFavorited(comicId: ComicId) -> Boolean`
**Contract**:
- Returns true if comic is favorited, false otherwise
- No error possible

### Commands

#### `markFavorite(comicId: ComicId) -> Favorite | Error`
**Contract**:
- Adds comic to favorites
- Throws: `NotFoundError` if comic not found
- If already favorited, updates `last_accessed_at`
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

Persistence layer for ImportBatch entities.

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

#### `getImportBatchBySource(sourceType: String, sourcePath: String) -> ImportBatch | Error`
**Contract**:
- Retrieves batch by source (for idempotency check)
- Throws: `NotFoundError` if not found

### Commands

#### `createImportBatch(sourceType: String, sourcePath: String, files: List<ImportFile>, metadata: Object) -> ImportBatch | Error`
**Contract**:
- Creates new import batch
- Generates UUID for ID
- Throws: `ValidationError` if sourceType invalid or files empty
- Throws: `DuplicateError` if same (sourceType, sourcePath) already exists as active batch
- Returns created ImportBatch with `completed_at = null`

#### `completeImportBatch(id: ImportBatchId, comicId: ComicId = null) -> ImportBatch | Error`
**Contract**:
- Marks batch as completed
- Sets `completed_at = NOW()`
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

All repositories throw these error types:

| Error | Meaning | HTTP Equivalent |
|-------|---------|-----------------|
| `NotFoundError` | Entity or relation not found | 404 |
| `DuplicateError` | Constraint violated (unique, etc.) | 409 |
| `ValidationError` | Data invalid (type, range, etc.) | 422 |
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
- Repositories must implement retry logic (exponential backoff)
- Max 3 retries before throwing `TransactionError`
- Timeout: 30 seconds per operation

---

## Batch Operations

For performance, repositories support batch commands:

- `createPages(chapterId, pages)` - insert multiple pages
- `updateReaderPositions(sessions)` - bulk reader position updates
- `deletePages(pageIds)` - bulk delete with reindexing

Batch operations are atomic: all succeed or all fail.

