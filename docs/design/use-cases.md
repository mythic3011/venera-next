# Use Cases Specification

**Language-agnostic application layer use cases (business workflows).**

---

## Overview

Use cases orchestrate repositories to implement business logic. Each use case:
- Defines input parameters and output results
- Specifies error conditions and handling
- Documents pre-conditions and post-conditions
- May involve multiple repositories (transactional)

Error model note:
- Error names in this document are conceptual categories.
- runtime/core implementations return `Result<T, CoreError>`-shaped outcomes; adapters may map them to thrown exceptions or transport responses.

Status model in this document:
- `Implemented (Core+DB)` = current canonical authority for runtime/core contract surface
- `Planned Canonical` = intended canonical direction, not current implementation authority
- `Deferred/Legacy` = historical or future-facing flow kept for reference only

Auth/permission note:
- Current runtime/core canonical slice does not define a user/auth domain model.
- Any `userId` attribution and permission enforcement belongs to adapter/auth layer policy until an explicit core auth contract is added.

---

## Comic Management Use Cases

### Implemented (Core+DB)

### UC-001: Create New Comic

**Purpose**: Add a new comic to the library.

**Actors**: User, System

**Pre-conditions**:
- Title is not empty

**Input**:
```
{
  title: String (non-empty)
  description: String (optional)
  originHint: String (optional, default "unknown")
  idempotencyKey: String (optional)
}
```

**Main Flow**:
1. System normalizes title (whitespace-collapsed display form) and derives a normalized title (search key)
2. System treats normalized title as a search key only; duplicate normalized titles may still represent separate canonical works
3. If `idempotencyKey` is present, the system computes a canonical input hash over the normalized input fields
4. If the same `idempotencyKey` was previously completed with the same input hash → replay the stored result, no mutation
5. If the same `idempotencyKey` is reused with a different canonical input hash → return `IDEMPOTENCY_CONFLICT`, no mutation
6. System creates Comic, ComicMetadata, and primary ComicTitle record in a single transaction
7. `comic_metadata.title` is set to the same value as `comic_titles.title` for the primary title row (denormalized cache; must be equal at creation time)
8. Return Comic, ComicMetadata, and primary ComicTitle

**Post-conditions**:
- Comic record exists in database
- ComicMetadata populated from input; `comic_metadata.title` equals primary `comic_titles.title`
- Primary ComicTitle record exists with `titleKind = "primary"`
- `created_at` / `updated_at` timestamps recorded on Comic and ComicMetadata
- If `idempotencyKey` provided: OperationIdempotency record exists with `status = "completed"` and serialized result
- No reader_sessions record is created at comic creation time

**Error Handling**:
- If the same `idempotencyKey` is reused with a different canonical input hash: return `IDEMPOTENCY_CONFLICT`, no changes
- If database fails: return `StorageError`, transaction rolled back

**Output**:
```
{
  comic: Comic (with assigned ID)
  metadata: ComicMetadata
  primaryTitle: ComicTitle
}
```

Invariant note:
- `metadata.title === primaryTitle.title` at creation. `comic_metadata.title` is a denormalized cache of the primary title and must equal it at the time of creation.

Diagnostics note:
- May record diagnostics event `comic.created` through diagnostics port when configured.

---

### UC-002: Import Comic from File

**Status**: Deferred/Legacy (not current core canonical authority)

**Purpose**: Import comic from CBZ, PDF, or directory.

**Actors**: User, System, FileSystem

**Pre-conditions**:
- Import file/directory exists and is readable
- File format is supported (CBZ, PDF, or directory with images)

**Input**:
```
{
  sourceType: String ("cbz" | "pdf" | "directory")
  sourcePath: String (legacy absolute path input; future canonical input should come via storage/import adapter contract)
  importMetadata: Object {
    title: String (optional, override from file)
    authorName: String (optional)
    tags: List<TagReference> (optional, projection shape)
  }
}
```

**Main Flow**:
1. System creates ImportBatch (status: in-progress)
2. System extracts/lists files from source
3. System validates all files are images (JPEG, PNG, etc.)
4. System sorts files by name/order
5. System creates ComicMetadata from importMetadata
6. System creates Comic if title provided
7. System creates Chapters with Pages for each image
8. System marks ImportBatch as completed
9. System emits `comic.imported` event
10. Return imported Comic and ImportBatch

**Post-conditions**:
- Comic created with ComicMetadata
- Pages created in canonical order
- ImportBatch marked completed with `completed_at`
- Reader position initialized
- Favorite optionally marked

**Error Handling**:
- If source file not readable: throw `NotFoundError`
- If no valid images: throw `ValidationError`
- If import already exists: throw `DuplicateError`
- If creation fails: ImportBatch deleted, transaction rolled back

**Output**:
```
{
  comic: Comic (newly created or matched)
  importBatch: ImportBatch (with completed_at)
  pagesCreated: Integer (count)
  event: DiagnosticsEvent (type: "comic.imported")
}
```

---

### UC-003: Update Comic Metadata

**Purpose**: Modify comic properties (title, description, cover).

**Actors**: User, System

**Pre-conditions**:
- Comic exists

**Input**:
```
{
  comicId: ComicId
  title: String (optional)
  description: String (optional)
  coverStorageObjectId: StorageObjectId (optional)
  authorName: String (optional)
  tags: List<TagReference> (optional, projection shape)
}
```

**Main Flow**:
1. System retrieves Comic by ID
2. If new title provided: system normalizes title for matching only (no duplicate-title rejection)
3. System updates ComicMetadata with provided fields
4. System emits `comic.updated` event with changes
5. Return updated Comic

**Post-conditions**:
- ComicMetadata modified
- `updated_at` timestamp refreshed
- Comic marked as modified

**Error Handling**:
- If comic not found: throw `NotFoundError`
- If title is invalid/empty after normalization rules: throw `ValidationError`

**Output**:
```
{
  comic: Comic (updated)
  changes: Object (fields that changed)
  event: DiagnosticsEvent (type: "comic.updated")
}
```

---

### UC-004: Delete Comic

**Status**: Planned Canonical

**Purpose**: Remove comic and all related data.

**Actors**: User, System

**Pre-conditions**:
- Comic exists
- Adapter/auth layer may enforce delete permissions (outside current core authority)

**Input**:
```
{
  comicId: ComicId
  confirmDeletion: Boolean (must be true)
}
```

**Main Flow**:
1. System retrieves Comic by ID
2. If `confirmDeletion` is false → ValidationError
3. System deletes Comic (cascades to chapters, pages, sessions, favorites)
4. System emits `comic.deleted` event
5. Return success

**Post-conditions**:
- Comic and all related records deleted
- Reader session cleared
- Favorite unmarked
- Cache files may remain (not deleted automatically)

**Error Handling**:
- If comic not found: throw `NotFoundError`
- If confirmation not provided: throw `ValidationError`
- If permission denied: throw `ForbiddenError`
- If deletion fails: throw `StorageError`, transaction rolled back

**Output**:
```
{
  success: Boolean
  deletedComicId: ComicId
  event: DiagnosticsEvent (type: "comic.deleted")
}
```

---

## Reader Management Use Cases

### Implemented (Core+DB)

Implemented use-case mapping in current core slice:
- ResolveReaderTarget (internal resolution step within OpenReader)
- OpenReader
- UpdateReaderPosition

### UC-005: Open Reader

**Purpose**: Resolve a canonical reader target and return the chapter, ordered page list, and active page order for display.

**Actors**: User, System, ReaderUI

**Pre-conditions**:
- Comic exists

**Input**:
```
{
  comicId: ComicId
  chapterId: ChapterId (optional)
  pageIndex: Integer (optional, 0-based)
  correlationId: String (optional, for diagnostics tracing)
}
```

**Main Flow**:
1. System resolves the reader target via the target resolution policy (see ResolveReaderTarget below)
2. System loads the resolved chapter
3. System loads all pages for the resolved chapter
4. System loads the active PageOrder for the chapter (if any)
5. System resolves the ordered page list using the page display/read order policy (see Page Display/Read Order below)
6. System validates the resolved pageIndex maps to a page entry in the ordered list
7. Return target, chapter, active page order, and ordered page entries

**Post-conditions**:
- No write to reader_sessions (read-only resolution; position writes are handled by UpdateReaderPosition)
- No modification to any persistent state

**Error Handling**:
- If comic not found: return `NOT_FOUND`
- If target cannot be resolved: return `READER_UNRESOLVED_LOCAL_TARGET`
- If resolved chapter disappears between resolution and load: return `READER_UNRESOLVED_LOCAL_TARGET`
- If no pages exist for resolved chapter: return `NOT_FOUND`
- If active PageOrder is incomplete: return `VALIDATION_ERROR`
- If resolved pageIndex does not map to a page: return `READER_INVALID_POSITION`

**Output**:
```
{
  target: ReaderOpenTarget {
    comicId: ComicId
    chapterId: ChapterId
    pageIndex: Integer
    pageId: PageId (optional)
    sourceKind: "local" | "remote"
    resolutionReason: "requested_chapter" | "saved_session" | "first_canonical_chapter"
  }
  chapter: Chapter
  activeOrder: PageOrderWithItems
  pages: List<ReaderPageEntry { page: Page, sortIndex: Integer }>
}
```

---

#### ResolveReaderTarget (internal resolution step of OpenReader)

**Purpose**: Determine the canonical chapter and page index to open, applying a strict fallback policy. This is not a standalone use case — it is an internal step of OpenReader.

**Fallback order**:

1. **Requested chapter** (when `chapterId` is provided):
   - Load chapter by `chapterId`.
   - If chapter not found, or chapter's `comicId` does not match the requested `comicId` → emit diagnostics warning and return `READER_UNRESOLVED_LOCAL_TARGET`.
   - Otherwise: use this chapter. `pageIndex` defaults to `0` if not provided.
   - Resolution reason: `"requested_chapter"`.

2. **Saved session** (when no `chapterId` provided and a reader session exists for the comic):
   - Load the saved session for the comic.
   - Validate the saved chapter: if chapter not found or its `comicId` does not match → `READER_UNRESOLVED_LOCAL_TARGET` (no silent repair).
   - Validate the saved page index: if no page in the chapter has `pageIndex` equal to the session's `pageIndex` → `READER_UNRESOLVED_LOCAL_TARGET` (no silent repair).
   - If a `pageId` is present in the session: load the page and verify it belongs to the same chapter and matches the saved `pageIndex`. Mismatch → `READER_UNRESOLVED_LOCAL_TARGET` (no silent repair).
   - Otherwise: use the saved chapter and page index.
   - Resolution reason: `"saved_session"`.

3. **First canonical chapter** (when no `chapterId` provided and no valid saved session exists):
   - Load all chapters for the comic.
   - For each chapter, compute aggregated source order: the minimum `sourceOrder` value across active, non-null chapter source links (where `linkStatus`, `sourceLinkStatus`, and `sourcePlatformStatus` are all `"active"`). Chapters with no qualifying source links have no aggregated source order.
   - Sort candidates by the following tuple (all ascending):
     1. Numbered chapters first: chapters with a finite `chapterNumber` sort before those without.
     2. `chapterNumber` ASC (numbered chapters only).
     3. Aggregated source order ASC (present values sort before absent).
     4. `createdAt` ASC.
     5. `id` ASC (lexicographic, tie-break).
   - If no chapters exist → `READER_UNRESOLVED_LOCAL_TARGET`.
   - Use the first chapter in the sorted list with `pageIndex = 0`.
   - Resolution reason: `"first_canonical_chapter"`.

**READER_UNRESOLVED_LOCAL_TARGET conditions**:
- Requested chapter not found or belongs to a different comic.
- Saved session chapter not found or belongs to a different comic.
- Saved session page index not found in the chapter.
- Saved session `pageId` present but does not match chapter + page index.
- No chapters exist on the comic (first-canonical fallback exhausted).

**Diagnostics**: Each `READER_UNRESOLVED_LOCAL_TARGET` outcome records a `reader.route.unresolved_target` diagnostics event at `warn` level with the specific `reason` field and `comicId`.

---

### UC-005b: Update Reader Position

**Purpose**: Persist the reader's current position in a comic.

**Actors**: User, System, ReaderUI

**Pre-conditions**:
- Comic exists
- Chapter exists and belongs to the comic
- `pageIndex` maps to an existing page in the chapter

**Input**:
```
{
  comicId: ComicId
  chapterId: ChapterId
  pageIndex: Integer (0-based)
  pageId: PageId (optional — evidence/cache for a concrete page row)
}
```

**Main Flow**:
1. System validates comic exists
2. System validates chapter exists and belongs to the comic
3. System validates `pageIndex` maps to an existing page in the chapter
4. If `pageId` is provided: system validates the page exists, belongs to the chapter, and its `pageIndex` matches the input `pageIndex`
5. If an existing session already has the same `chapterId`, `pageIndex`, and `pageId` → return the existing session with `status = "skipped_unchanged"`, no write
6. System upserts the reader session in `reader_sessions` with the new position
7. Return the persisted session

**Post-conditions**:
- `reader_sessions` record created or updated for the comic
- No other tables are written; scope stays within the reader session persistence boundary
- Last-write-wins: no locking; concurrent updates are safe

**Error Handling**:
- If comic not found: return `NOT_FOUND`
- If chapter not found or does not belong to comic: return `READER_INVALID_POSITION`
- If `pageIndex` does not map to a page: return `READER_INVALID_POSITION`
- If `pageId` provided but does not match chapter/page index: return `READER_INVALID_POSITION`

**Output**:
```
{
  session: ReaderSession (persisted position)
  status: "upserted" | "skipped_unchanged"
}
```

---

### UC-006: Get Reader Position

**Purpose**: Retrieve current reader position for resuming.

**Actors**: User, System, ReaderUI

**Pre-conditions**:
- Comic exists

**Input**:
```
{
  comicId: ComicId
}
```

**Main Flow**:
1. System retrieves ReaderSession for comic
2. If not found: system returns NotFound and lets orchestration/reader target resolution choose creation behavior
3. Return ReaderSession

**Post-conditions**:
- ReaderSession unchanged (read-only)
- No modification to position (read-only operation)

**Error Handling**:
- If comic not found: throw `NotFoundError`

**Output**:
```
{
  session: ReaderSession (current persisted position)
}
```

---

### UC-007: Clear Reader Position

**Status**: Planned Canonical

**Purpose**: Reset reader position to start.

**Actors**: User, System

**Pre-conditions**:
- Comic exists

**Input**:
```
{
  comicId: ComicId
}
```

**Main Flow**:
1. System retrieves ReaderSession
2. System clears stored session state or resets using canonical reader-target policy (for example first chapter by ordering policy, pageIndex = 0)
3. System emits `reader.position_cleared` event
4. Return updated ReaderSession

**Post-conditions**:
- ReaderSession position reset
- Favorite `last_accessed_at` NOT updated (reading didn't occur)

**Error Handling**:
- If comic not found: throw `NotFoundError`

**Output**:
```
{
  session: ReaderSession (reset to start)
  event: DiagnosticsEvent (type: "reader.position_cleared")
}
```

---

## Page Display/Read Order

When OpenReader resolves the ordered list of pages for a chapter, it applies the following policy:

**Primary path — active PageOrder exists**:
- Use the active `PageOrderWithItems` for the chapter.
- A PageOrder is considered **complete** when all of the following hold:
  - `pageOrder.pageCount` equals the total number of pages in the chapter.
  - `pageOrderItems.length` equals the total number of pages in the chapter.
  - Every item references a page that exists in the resolved chapter (no dangling page references).
  - Every page in the chapter appears in exactly one item (full coverage, no duplicates).
  - All `sortOrder` / `sortIndex` values among items are unique (sort-order gaps are allowed).
- If the active PageOrder is **incomplete** (any of the above conditions are violated): return `VALIDATION_ERROR`. There is no silent fallback when an active order exists but is incomplete.

**Fallback path — no active PageOrder**:
- Use a synthetic source order: pages sorted by `pageIndex` ASC.
- This fallback is only applied when there is no active PageOrder at all (null result from the repository).

---

## Favorites Management Use Cases

> **Not Implemented — current core pass**
>
> Favorite schema, domain model, ports, and exports are absent from the current runtime/core canonical slice. UC-008 through UC-010 below are retained as documentation of intended future behavior only. They carry no implementation authority and should not be treated as active contracts until a core favorites contract is explicitly introduced.

### Deferred/Legacy

### UC-008: Mark Comic as Favorite

**Purpose**: Add comic to user's favorites list.

**Actors**: User, System

**Pre-conditions**:
- Comic exists
- Comic not already favorited

**Input**:
```
{
  comicId: ComicId
}
```

**Main Flow**:
1. System retrieves Comic
2. System checks if already favorited → idempotent, return existing Favorite
3. System creates Favorite with `marked_at = CURRENT_TIMESTAMP`
4. System emits `favorite.marked` event
5. Return Favorite

**Post-conditions**:
- Favorite record created
- `marked_at` timestamp set
- `last_accessed_at` initialized to null

**Error Handling**:
- If comic not found: throw `NotFoundError`

**Output**:
```
{
  favorite: Favorite (newly created)
  event: DiagnosticsEvent (type: "favorite.marked")
}
```

---

### UC-009: Unmark Comic as Favorite

**Purpose**: Remove comic from favorites.

**Actors**: User, System

**Pre-conditions**:
- Comic is favorited

**Input**:
```
{
  comicId: ComicId
}
```

**Main Flow**:
1. System retrieves Favorite
2. System deletes Favorite
3. System emits `favorite.unmarked` event
4. Return success

**Post-conditions**:
- Favorite record deleted
- Comic still exists (not deleted)
- Reader position still exists

**Error Handling**:
- If comic not found: throw `NotFoundError`
- If not favorited: throw `NotFoundError`

**Output**:
```
{
  success: Boolean
  comicId: ComicId
  event: DiagnosticsEvent (type: "favorite.unmarked")
}
```

---

### UC-010: List Favorites

**Purpose**: Retrieve user's favorited comics.

**Actors**: User, System, UI

**Pre-conditions**:
- None

**Input**:
```
{
  limit: Integer (optional, default 100)
  offset: Integer (optional, default 0)
}
```

**Main Flow**:
1. System retrieves Favorites (paginated, ordered by last_accessed_at desc)
2. For each Favorite: retrieve full Comic with metadata
3. Return list of Favorites with associated Comics

**Post-conditions**:
- No modification
- Read-only operation

**Error Handling**:
- None (returns empty list if no favorites)

**Output**:
```
{
  favorites: List<{
    favorite: Favorite
    comic: Comic
  }>
  totalCount: Integer
  limit: Integer
  offset: Integer
}
```

---

## Chapter & Page Management Use Cases

### Deferred/Legacy

### UC-011: Create Chapters from Import

**Purpose**: Create ordered chapters from imported files.

**Actors**: System, ImportProcess

**Pre-conditions**:
- ImportBatch exists with files list
- All files are images or valid containers

**Input**:
```
{
  importBatchId: ImportBatchId
  groupingStrategy: String ("single_chapter" | "by_folder" | "by_file")
  chapterNumbering: String ("sequential" | "by_filename")
}
```

**Main Flow**:
1. System retrieves ImportBatch and files
2. Based on `groupingStrategy`:
   - `single_chapter`: Create one chapter with all pages
   - `by_folder`: Create chapter per folder
   - `by_file`: Create chapter per file (archive or container)
3. Based on `chapterNumbering`:
   - `sequential`: 1.0, 2.0, 3.0, ...
   - `by_filename`: Extract number from filename (1.5, etc.)
4. For each chapter: create all pages in order
5. Create PageOrder (source order)
6. System emits `chapters.created` event
7. Return created Chapters

**Post-conditions**:
- Chapters created with sequential numbers
- Pages created in order
- PageOrder set to 'source'

**Error Handling**:
- If ImportBatch not found: throw `NotFoundError`
- If invalid strategy: throw `ValidationError`
- If parsing fails: throw `ValidationError`

**Output**:
```
{
  chaptersCreated: Integer
  chapters: List<Chapter>
  pagesPerChapter: List<Integer>
  event: DiagnosticsEvent (type: "chapters.created")
}
```

---

### UC-012: Reorder Pages in Chapter

**Purpose**: Set custom page ordering for a chapter.

**Actors**: User, System

**Pre-conditions**:
- Chapter exists
- All page IDs belong to chapter

**Input**:
```
{
  chapterId: ChapterId
  pageIds: List<PageId> (user-specified order)
}
```

**Main Flow**:
1. System retrieves Chapter
2. System validates all page IDs exist in chapter
3. System validates all chapter pages are included
4. System updates PageOrder with `order_type = 'user_override'`
5. System stores user page order through `PageOrder` + `PageOrderItem` entries (not delimited strings)
6. System emits `chapter.pages_reordered` event
7. Return updated PageOrder

**Post-conditions**:
- PageOrder updated with user override
- Reader position may need adjustment if current page moved
- `updated_at` timestamp refreshed

**Error Handling**:
- If chapter not found: throw `NotFoundError`
- If page IDs invalid: throw `ValidationError`
- If not all pages included: throw `ValidationError`

**Output**:
```
{
  pageOrder: PageOrder
  newOrder: List<PageId>
  event: DiagnosticsEvent (type: "chapter.pages_reordered")
}
```

---

## Search & Browse Use Cases

### Deferred/Legacy

### UC-013: Search Comics

**Purpose**: Full-text search across comics.

**Actors**: User, System, SearchUI

**Pre-conditions**:
- Search index is current (if applicable)

**Input**:
```
{
  query: String (search terms)
  limit: Integer (optional, default 50)
  offset: Integer (optional, default 0)
}
```

**Main Flow**:
1. System performs full-text search on `title`, `description`, `author`
2. System orders results by relevance
3. System paginates results
4. For each comic: retrieve metadata and reader session
5. Return search results

**Post-conditions**:
- No modification
- Read-only operation

**Error Handling**:
- If search index unavailable: throw `StorageError`
- Returns empty list if no matches

**Output**:
```
{
  results: List<Comic>
  totalMatches: Integer
  query: String
  limit: Integer
  offset: Integer
}
```

Diagnostics note:
- Raw query may be returned to caller, but diagnostics should persist `queryHash` and optional sanitized preview.

---

### UC-014: List All Comics

**Purpose**: Browse all comics in library.

**Actors**: User, System, BrowseUI

**Pre-conditions**:
- None

**Input**:
```
{
  sortBy: String ("title" | "created" | "updated" | "last_read")
  sortOrder: String ("asc" | "desc")
  limit: Integer (optional, default 50)
  offset: Integer (optional, default 0)
}
```

**Main Flow**:
1. System retrieves all Comics
2. System sorts by specified field
3. System paginates
4. For each comic: retrieve metadata, reader session, favorite status
5. Return paginated comics

**Post-conditions**:
- No modification
- Read-only operation

**Error Handling**:
- If invalid sortBy: throw `ValidationError`
- Returns empty list if no comics

**Output**:
```
{
  comics: List<Comic>
  totalCount: Integer
  limit: Integer
  offset: Integer
}
```

---

## Diagnostics & Events

All use cases emit `DiagnosticsEvent` for audit trail and monitoring:

```
Entity: DiagnosticsEvent
  id: String (UUID v4)
  schemaVersion: String ("1.0.0")
  timestamp: Timestamp (UTC)
  eventType: String (e.g., "comic.created", "reader.position_changed")
  userId: String (optional, adapter-provided attribution, not core-owned identity)
  correlationId: String (trace ID)
  resourceId: String (entity ID affected)
  resourceType: String (entity type)
  action: String (created, updated, deleted, etc.)
  payload: Object (event-specific data)
  severity: String ("info", "warning", "error")
  duration: Integer (milliseconds)
  queryHash: String (optional, salted per debug bundle/export scope; redaction policy applies)
```

**DiagnosticsEvent Examples**:
```
{
  eventType: "comic.created",
  resourceType: "Comic",
  action: "created",
  payload: { comicId, normalizedTitle }
}

{
  eventType: "reader.position_changed",
  resourceType: "ReaderSession",
  action: "updated",
  payload: { comicId, chapterId, pageIndex }
}
```

---

## Use Case Error Matrix

| Use Case | Status | NotFound | Duplicate | IdempotencyConflict | Validation | ReaderUnresolved | ReaderInvalidPos | Permission* | Storage |
|----------|--------|----------|-----------|---------------------|------------|-----------------|-----------------|-------------|---------|
| Create Comic | Implemented | - | - | X | X | - | - | - | X |
| Import Comic | Deferred/Legacy | X | X | - | X | - | - | - | X |
| Update Metadata | Implemented | X | - | - | X | - | - | - | X |
| Delete Comic | Planned Canonical | X | - | - | X | - | - | X | X |
| Open Reader | Implemented | X | - | - | X | X | X | - | X |
| Update Position | Implemented | X | - | - | - | - | X | - | X |
| Get Position | Implemented | X | - | - | - | - | - | - | - |
| Clear Position | Planned Canonical | X | - | - | - | - | - | - | X |
| Mark Favorite | Deferred/Legacy | X | - | - | - | - | - | - | X |
| Unmark Favorite | Deferred/Legacy | X | - | - | - | - | - | - | X |
| List Favorites | Deferred/Legacy | - | - | - | - | - | - | - | - |
| Create Chapters | Deferred/Legacy | X | - | - | X | - | - | - | X |
| Reorder Pages | Deferred/Legacy | X | - | - | X | - | - | - | X |
| Search Comics | Deferred/Legacy | - | - | - | X | - | - | - | X |
| List Comics | Deferred/Legacy | - | - | - | X | - | - | - | - |

\* `Permission` is adapter/auth-layer concern in current core slice, not core-owned domain authority.

`ReaderUnresolved` = `READER_UNRESOLVED_LOCAL_TARGET` — emitted when the resolution policy exhausts all fallbacks or encounters a stale/invalid saved target.

`ReaderInvalidPos` = `READER_INVALID_POSITION` — emitted when a position write or page lookup references a chapter/page that exists but does not match the requested coordinates.
