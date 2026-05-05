# Use Cases Specification

**Language-agnostic application layer use cases (business workflows).**

---

## Overview

Use cases orchestrate repositories to implement business logic. Each use case:
- Defines input parameters and output results
- Specifies error conditions and handling
- Documents pre-conditions and post-conditions
- May involve multiple repositories (transactional)

---

## Comic Management Use Cases

### UC-001: Create New Comic

**Purpose**: Add a new comic to the library.

**Actors**: User, System

**Pre-conditions**:
- User has write permissions
- Title is not empty

**Input**:
```
{
  title: String (non-empty)
  description: String (optional)
}
```

**Main Flow**:
1. System normalizes title (lowercase, remove punctuation)
2. System checks if normalized title exists → DuplicateError
3. System creates Comic with ComicMetadata
4. System creates default ReaderSession (chapter 0, page 0)
5. System emits `comic.created` event
6. Return new Comic with ID

**Post-conditions**:
- Comic exists in database
- ComicMetadata populated from input
- ReaderSession initialized
- Comic marked as modified

**Error Handling**:
- If duplicate title: throw `DuplicateError`, no changes
- If write permission denied: throw `ForbiddenError`
- If database fails: throw `StorageError`, transaction rolled back

**Output**:
```
{
  comic: Comic (with assigned ID)
  event: DiagnosticsEvent (type: "comic.created")
}
```

---

### UC-002: Import Comic from File

**Purpose**: Import comic from CBZ, PDF, or directory.

**Actors**: User, System, FileSystem

**Pre-conditions**:
- Import file/directory exists and is readable
- File format is supported (CBZ, PDF, or directory with images)

**Input**:
```
{
  sourceType: String ("cbz" | "pdf" | "directory")
  sourcePath: String (absolute path)
  importMetadata: Object {
    title: String (optional, override from file)
    authorName: String (optional)
    genreTags: List<String> (optional)
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
- User has write permissions

**Input**:
```
{
  comicId: ComicId
  title: String (optional, if new, check for duplicates)
  description: String (optional)
  coverLocalPath: String (optional)
  authorName: String (optional)
  genreTags: List<String> (optional)
}
```

**Main Flow**:
1. System retrieves Comic by ID
2. If new title provided:
   - System normalizes and checks for duplicates → DuplicateError
3. System updates ComicMetadata with provided fields
4. System emits `comic.updated` event with changes
5. Return updated Comic

**Post-conditions**:
- ComicMetadata modified
- `updated_at` timestamp refreshed
- Comic marked as modified

**Error Handling**:
- If comic not found: throw `NotFoundError`
- If title duplicate: throw `DuplicateError`, no changes
- If permission denied: throw `ForbiddenError`

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

**Purpose**: Remove comic and all related data.

**Actors**: User, System

**Pre-conditions**:
- Comic exists
- User has delete permissions

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
4. If comic is favorited: System updates `favorite.last_accessed_at`
5. System emits `reader.position_changed` event
6. Return updated ReaderSession

**Post-conditions**:
- ReaderSession updated
- Favorite timestamp updated (if favorited)
- Reader position persisted
- `updated_at` timestamp refreshed

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
2. If not found: System creates default session (chapter 0, page 0)
3. Return ReaderSession

**Post-conditions**:
- ReaderSession exists (may be newly created)
- No modification to position (read-only operation)

**Error Handling**:
- If comic not found: throw `NotFoundError`

**Output**:
```
{
  session: ReaderSession (current position or default)
}
```

---

### UC-007: Clear Reader Position

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
2. System resets position to chapter 0, page 0
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
3. System creates Favorite with `marked_at = NOW()`
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
5. System stores user page order
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
  timestamp: Timestamp (UTC)
  eventType: String (e.g., "comic.created", "reader.position_changed")
  userId: String (optional, who triggered)
  correlationId: String (trace ID)
  resourceId: String (entity ID affected)
  resourceType: String (entity type)
  action: String (created, updated, deleted, etc.)
  payload: Object (event-specific data)
  severity: String ("info", "warning", "error")
  duration: Integer (milliseconds)
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

| Use Case | NotFound | Duplicate | Validation | Permission | Storage |
|----------|----------|-----------|-----------|-----------|---------|
| Create Comic | - | X | X | X | X |
| Import Comic | X | X | X | - | X |
| Update Metadata | X | X | X | X | X |
| Delete Comic | X | - | X | X | X |
| Read Position | X | - | X | - | X |
| Get Position | X | - | - | - | - |
| Clear Position | X | - | - | - | X |
| Mark Favorite | X | - | - | - | X |
| Unmark Favorite | X | - | - | - | X |
| List Favorites | - | - | - | - | - |
| Create Chapters | X | - | X | - | X |
| Reorder Pages | X | - | X | - | X |
| Search Comics | - | - | X | - | X |
| List Comics | - | - | X | - | - |

