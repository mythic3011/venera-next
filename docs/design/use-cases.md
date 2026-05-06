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
  idempotencyKey: String (optional)
}
```

**Main Flow**:
1. System normalizes title (lowercase, remove punctuation)
2. System treats normalized title as a search key only; duplicate normalized titles may still represent separate canonical works
3. If `idempotencyKey` is present, the system replays only a previously completed result with the same canonical input hash
4. If the same `idempotencyKey` is reused with different canonical input, the system returns `IDEMPOTENCY_CONFLICT` and performs no mutation
5. System creates Comic with ComicMetadata
6. System emits `comic.created` event
7. Return new Comic with ID

**Post-conditions**:
- Comic exists in database
- ComicMetadata populated from input
- `created_at` / `updated_at` timestamps recorded

**Error Handling**:
- If the same `idempotencyKey` is reused with a different canonical input: throw `IDEMPOTENCY_CONFLICT`, no changes
- If database fails: throw `StorageError`, transaction rolled back

**Output**:
```
{
  comic: Comic (with assigned ID)
  metadata: ComicMetadata
  primaryTitle: ComicTitle
}
```

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
- ResolveReaderTarget
- OpenReader
- UpdateReaderPosition

### UC-005: Read Comic (Update Position)

**Purpose**: Record reader's current position in comic.

**Actors**: User, System, ReaderUI

**Pre-conditions**:
- Comic exists
- Chapter exists in comic
- Page index is valid (< page count)

**Input**:
```
{
  comicId: ComicId
  chapterId: ChapterId
  pageIndex: Integer (0-based)
}
```

**Main Flow**:
1. System validates chapter belongs to comic
2. System validates pageIndex < page count in chapter
3. System updates ReaderSession with new position
4. System emits `reader.position_changed` event
5. Return updated ReaderSession

**Post-conditions**:
- ReaderSession updated
- Reader position persisted
- `updated_at` timestamp refreshed
- Favorite timestamp coupling is deferred to future favorite/read activity policy

**Error Handling**:
- If comic not found: throw `NotFoundError`
- If chapter not found or not in comic: throw `NotFoundError`
- If pageIndex invalid: throw `ValidationError`
- Last-write-wins: no locking, concurrent updates are safe

**Output**:
```
{
  session: ReaderSession (updated position)
  event: DiagnosticsEvent (type: "reader.position_changed")
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

## Favorites Management Use Cases

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

| Use Case | Status | NotFound | Duplicate | IdempotencyConflict | Validation | Permission* | Storage |
|----------|--------|----------|-----------|---------------------|------------|-------------|---------|
| Create Comic | Implemented | - | - | X | X | - | X |
| Import Comic | Deferred/Legacy | X | X | - | X | - | X |
| Update Metadata | Implemented | X | - | - | X | - | X |
| Delete Comic | Planned Canonical | X | - | - | X | X | X |
| Read Position | Implemented | X | - | - | X | - | X |
| Get Position | Implemented | X | - | - | - | - | - |
| Clear Position | Planned Canonical | X | - | - | - | - | X |
| Mark Favorite | Deferred/Legacy | X | - | - | - | - | X |
| Unmark Favorite | Deferred/Legacy | X | - | - | - | - | X |
| List Favorites | Deferred/Legacy | - | - | - | - | - | - |
| Create Chapters | Deferred/Legacy | X | - | - | X | - | X |
| Reorder Pages | Deferred/Legacy | X | - | - | X | - | X |
| Search Comics | Deferred/Legacy | - | - | - | X | - | X |
| List Comics | Deferred/Legacy | - | - | - | X | - | - |

\* `Permission` is adapter/auth-layer concern in current core slice, not core-owned domain authority.
