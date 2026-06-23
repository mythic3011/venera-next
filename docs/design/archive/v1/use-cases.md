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
- `Target` = corrected pre-stable design contract; runtime/core implementation must catch up before behavior is claimed complete
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
5. If the same `idempotencyKey` already exists as non-expired `in_progress` or a `failed` record still inside the retry TTL → fail closed; current implementation returns a non-replayable error and performs no mutation
6. If the same `idempotencyKey` is reused with a different canonical input hash → return `IDEMPOTENCY_CONFLICT`, no mutation
7. If the same `idempotencyKey` has a stale `in_progress` record or retryable `failed` record with the same input hash, system atomically reclaims the key before mutation
8. System creates Comic, ComicMetadata, and primary ComicTitle record in a single transaction
9. `comic_metadata.title` is set to the same value as `comic_titles.title` for the primary title row (denormalized cache; must be equal at creation time)
10. Return Comic, ComicMetadata, and primary ComicTitle

**Post-conditions**:
- Comic record exists in database
- ComicMetadata populated from input; `comic_metadata.title` equals primary `comic_titles.title`
- Primary ComicTitle record exists with `titleKind = "primary"`
- `created_at` / `updated_at` timestamps recorded on Comic and ComicMetadata
- If `idempotencyKey` provided: OperationIdempotency record exists with `status = "completed"` and serialized result
- No reader_sessions record is created at comic creation time

**Error Handling**:
- If the same `idempotencyKey` already exists as non-expired `in_progress` or non-retryable `failed`: return a fail-closed non-replayable error, no changes
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
1. System creates ImportBatch (status: `in_progress`)
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
- If creation fails: ImportBatch is marked `failed` or `cancelled` by the import adapter; canonical writes are rolled back

**Output**:
```
{
  comic: Comic (newly created or matched)
  importBatch: ImportBatch (with completed_at)
  pagesCreated: Integer (count)
  event: DiagnosticsEvent (eventName: "comic.imported")
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
  coverStatus: "none" | "pending" | "local_only" | "synced" (optional)
  coverPageId: PageId (optional)
  coverStorageObjectId: StorageObjectId (optional)
  authorName: String (optional)
  tags: List<TagReference> (optional, projection shape)
}
```

**Main Flow**:
1. System retrieves Comic by ID
2. If new title provided: system normalizes title for matching only (no duplicate-title rejection)
3. If cover references are provided, system validates the cover lifecycle rules:
   - `coverStatus = "none"` requires both cover references to be absent
   - `coverStatus = "local_only"` requires `coverPageId` or `coverStorageObjectId`
   - `coverStatus = "synced"` requires `coverStorageObjectId` with readable authoritative placement
   - if both cover references are present, `coverPageId.storageObjectId` must equal `coverStorageObjectId`
4. System updates ComicMetadata with provided fields
5. System emits `comic.updated` event with changes
6. Return updated Comic

**Post-conditions**:
- ComicMetadata modified
- `updated_at` timestamp refreshed
- Comic marked as modified

**Error Handling**:
- If comic not found: throw `NotFoundError`
- If title is invalid/empty after normalization rules: throw `ValidationError`
- If cover references conflict or required cover bytes are unavailable: throw `ValidationError`

**Output**:
```
{
  comic: Comic (updated)
  changes: Object (fields that changed)
  event: DiagnosticsEvent (eventName: "comic.updated")
}
```

---

### UC-004: Remove Comic from Library

**Status**: Planned Canonical

**Purpose**: Hide a comic from default library surfaces without destroying reader progress or child data.

**Actors**: User, System

**Pre-conditions**:
- Comic exists
- Adapter/auth layer may enforce delete permissions (outside current core authority)

**Input**:
```
{
  comicId: ComicId
  confirmRemoval: Boolean (must be true)
}
```

**Main Flow**:
1. System retrieves Comic by ID
2. If `confirmRemoval` is false → ValidationError
3. System updates `Comic.libraryStatus = "removed"` and sets `removedAt`
4. System emits `comic.removed` event
5. Return success

**Post-conditions**:
- Comic row remains in database with `libraryStatus = "removed"`
- Chapters, Pages, PageOrders, ReaderSession, SourceLinks, and collection membership remain intact
- Default library/search/browse surfaces exclude removed comics unless explicitly requested
- Storage/cache files are not deleted

**Error Handling**:
- If comic not found: throw `NotFoundError`
- If confirmation not provided: throw `ValidationError`
- If permission denied: throw `ForbiddenError`
- If update fails: throw `StorageError`, transaction rolled back

**Output**:
```
{
  success: Boolean
  removedComicId: ComicId
  event: DiagnosticsEvent (eventName: "comic.removed")
}
```

---

### UC-004b: Permanently Delete Comic

**Status**: Planned Canonical

**Purpose**: Irreversibly purge a comic and all dependent records.

**Actors**: User, System

**Pre-conditions**:
- Comic exists
- User explicitly requests permanent deletion, not normal library removal
- Adapter/auth layer may enforce delete permissions (outside current core authority)

**Input**:
```
{
  comicId: ComicId
  confirmPermanentDeletion: Boolean (must be true)
}
```

**Main Flow**:
1. System retrieves Comic by ID
2. If `confirmPermanentDeletion` is false -> ValidationError
3. System explicitly deletes or cascades ReaderSession lifecycle rows for the Comic before Chapter/Page cascades can invalidate `reader_sessions.pageId`
4. System deletes Comic, cascading to Chapters, Pages, PageOrders, SourceLinks, and UserCollectionItem rows
5. System emits `comic.deleted` event
6. Return success

**Post-conditions**:
- Comic and dependent database rows are deleted
- Storage/cache byte cleanup is a separate storage lifecycle concern unless explicitly included by a future storage purge contract

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
  event: DiagnosticsEvent (eventName: "comic.deleted")
}
```

---

## Source Link Management Use Cases

### Planned Canonical

These use cases own the cross-platform identity/provenance write path. `SourceLink` merges source provenance into an existing canonical Comic; it does not create a user-defined collection and does not make provider IDs canonical comic identity.

### UC-SRC-001: Add SourceLink to Comic

**Purpose**: Attach a provider/platform work to an existing canonical Comic.

**Actors**: User, System, SourceRuntime

**Pre-conditions**:
- Comic exists
- SourcePlatform exists and is not `deprecated`
- `(sourcePlatformId, remoteWorkId)` is not already linked in the current schema

**Input**:
```
{
  comicId: ComicId
  sourcePlatformId: SourcePlatformId
  remoteWorkId: String
  remoteUrl: String (optional)
  displayTitle: String (optional)
  linkStatus: "active" | "candidate" (optional, default "candidate" for automated matches, "active" for explicit manual attach)
  confidence: "manual" | "auto_high" | "auto_low"
}
```

**Main Flow**:
1. System validates Comic and SourcePlatform exist
2. System rejects `SourcePlatform.status = "deprecated"`
3. System validates `(sourcePlatformId, remoteWorkId)` uniqueness using the DB unique constraint
4. System creates SourceLink
5. System recomputes and updates `Comic.originHint` in the same transaction
6. System emits `source_link.added` event
7. Return SourceLink and updated Comic

**Post-conditions**:
- SourceLink exists for the Comic
- `Comic.originHint` reflects active local/remote content-bearing SourceLink membership

**Error Handling**:
- If comic or platform not found: throw `NotFoundError`
- If provider work is already linked: throw `DuplicateError`
- If platform is deprecated or input is invalid: throw `ValidationError`

### UC-SRC-002: Update SourceLink Status

**Purpose**: Approve, reject, stale, or reactivate a comic-level source provenance edge.

**Input**:
```
{
  sourceLinkId: SourceLinkId
  linkStatus: "active" | "candidate" | "rejected" | "stale"
  confidence: "manual" | "auto_high" | "auto_low" (optional)
}
```

**Main Flow**:
1. System loads SourceLink and parent Comic
2. System updates SourceLink lifecycle fields
3. System recomputes and updates `Comic.originHint` in the same transaction
4. System emits `source_link.updated` event
5. Return SourceLink and updated Comic

**Post-conditions**:
- SourceLink lifecycle state is updated
- `Comic.originHint` remains transactionally aligned with active source-link membership

**Error Handling**:
- If SourceLink not found: throw `NotFoundError`
- If lifecycle value is invalid: throw `ValidationError`

### UC-SRC-003: Upsert ChapterSourceLink

**Purpose**: Attach source-specific chapter provenance and ordering evidence to a canonical Chapter.

**Input**:
```
{
  chapterId: ChapterId
  sourceLinkId: SourceLinkId
  remoteChapterId: String
  remoteUrl: String (optional)
  remoteLabel: String (optional)
  sourceOrder: Integer (optional)
  linkStatus: "active" | "inactive" | "stale"
  confidence: "manual" | "auto_high" | "auto_low"
}
```

**Main Flow**:
1. System validates Chapter and SourceLink exist
2. System validates the Chapter belongs to the same Comic as the SourceLink
3. System upserts ChapterSourceLink by `(sourceLinkId, remoteChapterId)`
4. System stores `sourceOrder` as ordering evidence when provided
5. System emits `chapter_source_link.upserted` event
6. Return ChapterSourceLink

**Post-conditions**:
- Chapter-level source provenance exists or is updated
- First-canonical-chapter fallback can aggregate `sourceOrder` from active ChapterSourceLinks

**Error Handling**:
- If Chapter or SourceLink not found: throw `NotFoundError`
- If Chapter/SourceLink belong to different Comics: throw `ValidationError`

---

## Reader Management Use Cases

### Core+DB Contract

Corrected target use-case mapping for the current core slice. Runtime implementation may lag schema-repair fields such as `ReaderSession.pageId` authority until a dedicated implementation catch-up slice lands:
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
  pageId: PageId (optional)
  correlationId: String (optional, for diagnostics tracing)
}
```

**Main Flow**:
1. System resolves the reader target via the target resolution policy (see ResolveReaderTarget below)
2. System loads the resolved chapter
3. System loads all pages for the resolved chapter
4. System loads the active PageOrder for the chapter (if any)
5. System resolves the ordered page list using the page display/read order policy (see Page Display/Read Order below)
6. System validates the resolved page target maps to a page entry in the ordered list
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
- If resolved page target does not map to a page: return `READER_INVALID_POSITION`

**Output**:
```
{
  target: ReaderOpenTarget {
    comicId: ComicId
    chapterId: ChapterId
    pageId: PageId
    pageIndex: Integer (derived from Page)
    sourceKind: "local" | "remote"
    resolutionReason: "requested_page" | "requested_chapter" | "saved_session" | "first_canonical_chapter"
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

1. **Requested page** (when `pageId` is provided):
   - Load page by `pageId` and its parent chapter.
   - If page or chapter is not found, or the parent chapter's `comicId` does not match the requested `comicId` → emit diagnostics warning and return `READER_UNRESOLVED_LOCAL_TARGET`.
   - If `chapterId` is also provided and does not match the page's parent chapter → return `READER_INVALID_POSITION`; explicit inputs must not conflict.
   - Otherwise: use this page and derive `chapterId` + `pageIndex` from the page row.
   - Resolution reason: `"requested_page"`.

2. **Requested chapter** (when `chapterId` is provided and `pageId` is absent):
   - Load chapter by `chapterId`.
   - If chapter not found, or chapter's `comicId` does not match the requested `comicId` → emit diagnostics warning and return `READER_UNRESOLVED_LOCAL_TARGET`.
   - Otherwise: use this chapter. `pageIndex` defaults to `0` if not provided.
   - Resolution reason: `"requested_chapter"`.

3. **Saved session** (when no explicit page/chapter target is provided and an active reader session exists for the comic):
   - Load the active saved session for the comic.
   - Load the page referenced by `session.pageId` and derive its parent chapter and `pageIndex`.
   - Validate the saved page target: if page or chapter is not found, or the chapter's `comicId` does not match the requested `comicId` → `READER_UNRESOLVED_LOCAL_TARGET` (no silent repair).
   - If `session.sourceLinkId` is present but the source link is stale/deprecated, treat it as read-context evidence only and prefer active alternative ChapterSourceLink/Page provenance when available; stale source context must not invalidate the canonical saved page by itself.
   - Otherwise: use the derived chapter and page index.
   - Resolution reason: `"saved_session"`.

4. **First canonical chapter** (when no explicit target is provided and no valid active saved session exists):
   - Load all chapters for the comic.
   - For each chapter, compute aggregated source order: the minimum `sourceOrder` value across active, non-null chapter source links (where `linkStatus`, `sourceLinkStatus`, and `sourcePlatformStatus` are all `"active"`). Chapters with no qualifying source links have no aggregated source order.
   - Sort candidates by the following tuple (all ascending):
     1. Numbered chapters first: chapters with a valid decimal-string `chapterNumber` sort before those without.
     2. `chapterNumber` ASC using decimal/numeric comparison (numbered chapters only).
     3. Aggregated source order ASC (present values sort before absent).
     4. `createdAt` ASC.
     5. `id` ASC (lexicographic, tie-break).
   - If no chapters exist → `READER_UNRESOLVED_LOCAL_TARGET`.
   - Use the first page in the first sorted chapter by `pageIndex` ascending; `pageId` is the persisted/open-target authority and `pageIndex` is derived from that Page.
   - Resolution reason: `"first_canonical_chapter"`.

**READER_UNRESOLVED_LOCAL_TARGET conditions**:
- Requested chapter not found or belongs to a different comic.
- Requested page not found or belongs to a different comic through its chapter.
- Saved session page not found or belongs to a different comic through its chapter.
- No chapters exist on the comic (first-canonical fallback exhausted).

**Diagnostics**: Each `READER_UNRESOLVED_LOCAL_TARGET` outcome records a `reader.route.unresolved_target` diagnostics event at `warn` level with the specific `reason` field and `comicId`.

---

### UC-005b: Update Reader Position

**Purpose**: Persist the reader's current position in a comic.

**Actors**: User, System, ReaderUI

**Pre-conditions**:
- Comic exists
- Page exists and its Chapter belongs to the comic

**Input**:
```
{
  comicId: ComicId
  pageId: PageId
  sourceLinkId: SourceLinkId (optional, last read-source context)
  sessionState: "active" | "suspended" | "completed" | "abandoned" (optional, defaults to "active")
}
```

**Main Flow**:
1. System validates comic exists
2. System loads `pageId` and its parent Chapter
3. System validates the parent Chapter belongs to the comic
4. If `sourceLinkId` is provided, system validates it belongs to the same comic
5. If an existing active session already has the same `pageId`, `sourceLinkId`, and requested `sessionState` → return the existing session with `status = "skipped_unchanged"`, no write
6. System upserts the reader session in `reader_sessions` with the new `pageId` position authority, optional read-source context, and lifecycle state
7. Return the persisted session

**Post-conditions**:
- `reader_sessions` record created or updated for the comic
- No other tables are written; scope stays within the reader session persistence boundary
- Current persistence is last-write-wins within the local single-runtime model
- No multi-device conflict-resolution contract is defined in the current core slice

**Error Handling**:
- If comic not found: return `NOT_FOUND`
- If `pageId` is not found: return `READER_INVALID_POSITION`
- If the referenced Page's Chapter does not belong to comic: return `READER_INVALID_POSITION`
- If `sourceLinkId` is provided but does not belong to comic: return `READER_INVALID_POSITION`

**Output**:
```
{
  session: ReaderSession (persisted position)
  status: "written" | "skipped_unchanged"
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
1. System retrieves the active ReaderSession for comic
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
1. System retrieves the active ReaderSession for the comic
2. If no active session exists, system returns success with `status = "no_active_session"`
3. System marks the active session `sessionState = "abandoned"` in place; it does not hard-delete the lifecycle row
4. System emits `reader.position_cleared` event
5. Return the abandoned ReaderSession or no-op status

**Post-conditions**:
- No active ReaderSession remains for the comic
- Historical ReaderSession lifecycle evidence is retained
- Favorite `last_accessed_at` NOT updated (reading didn't occur)

**Error Handling**:
- If comic not found: throw `NotFoundError`

**Output**:
```
{
  session: ReaderSession (abandoned, optional when no active session existed)
  status: "abandoned" | "no_active_session"
  event: DiagnosticsEvent (eventName: "reader.position_cleared")
}
```

---

## Page Display/Read Order

When OpenReader resolves the ordered list of pages for a chapter, it applies the following policy:

**Primary path — active PageOrder exists**:
- Use the `PageOrderWithItems` whose `PageOrder.status = "active"` for the chapter.
- A PageOrder is considered **complete** when all of the following hold:
  - `pageOrderItems.length` equals the total number of pages in the chapter.
  - Every item references a page that exists in the resolved chapter (no dangling page references).
  - Every page in the chapter appears in exactly one item (full coverage, no duplicates).
  - All `sortOrder` / `sortIndex` values among items are unique (sort-order gaps are allowed).
- If the active PageOrder is **incomplete** (any of the above conditions are violated): return `VALIDATION_ERROR`. There is no silent fallback when an active order exists but is incomplete.

**Fallback path — no active PageOrder**:
- Use a synthetic source order: pages sorted by `pageIndex` ASC.
- This fallback is only applied when there is no active PageOrder at all (null result from the repository).

---

## Page Asset Availability

OpenReader returns canonical page rows and read order; byte availability is resolved by the storage/image-loading path.

Rules:
- `Page.storageObjectId = null` means no local storage object has been assigned yet.
- `Page.storageObjectId != null` does not guarantee readable bytes. The loader must resolve StoragePlacements and require at least one placement whose role/status is readable for the current backend policy.
- If no readable placement exists, the loader returns `STORAGE_OBJECT_UNAVAILABLE` or an explicit placeholder/retry state. It must not treat a StorageObject row by itself as success.
- Remote fallback from stale/missing local bytes must be a deliberate source-runtime decision using SourceLink/ChapterSourceLink provenance, not an implicit storage lookup side effect.

---

## User Collection Management Use Cases

> **Planned Canonical — not current core implementation**
>
> UserCollection and UserCollectionItem define user-owned cross-platform grouping. They are separate from SourceLink identity merge/provenance and from source account favorite state.

### UC-COL-001: Create User Collection

**Purpose**: Create a user-defined grouping of comics.

**Actors**: User, System

**Pre-conditions**:
- Display name is not empty

**Input**:
```
{
  displayName: String
  description: String (optional)
  coverStorageObjectId: StorageObjectId (optional)
  sortOrder: "manual" | "title" | "updated_at" | "last_read" (optional, default "manual")
}
```

**Main Flow**:
1. System normalizes and validates `displayName`
2. If `coverStorageObjectId` is provided, system validates the StorageObject exists; readable placement is required before UI claims bytes are available
3. System creates UserCollection
4. System emits `collection.created` event
5. Return UserCollection

**Post-conditions**:
- Collection exists with no items

**Error Handling**:
- If display name is empty: throw `ValidationError`
- If cover storage object does not exist: throw `NotFoundError`

### UC-COL-002: Add Comic to Collection

**Purpose**: Add a comic from any platform/source to a user collection.

**Input**:
```
{
  collectionId: UserCollectionId
  comicId: ComicId
  sortIndex: Integer (optional; required for exact manual insertion)
  pinnedAt: Timestamp (optional)
  allowRemoved: Boolean (optional, default false)
}
```

**Main Flow**:
1. System validates collection and comic exist
2. If the Comic has `libraryStatus = "removed"` and `allowRemoved` is not true, system rejects the add
3. System rejects duplicate `(collectionId, comicId)` membership
4. System assigns or shifts `sortIndex` atomically for manual order
5. System creates UserCollectionItem
6. System emits `collection.item_added` event
7. Return UserCollectionItem

**Post-conditions**:
- Comic is a member of the collection
- Removed comics may be added only when the caller explicitly allows removed-library items

**Error Handling**:
- If collection or comic not found: throw `NotFoundError`
- If comic is removed and `allowRemoved` is not true: throw `ValidationError`
- If membership already exists: throw `DuplicateError`
- If sort index conflicts and cannot be repaired atomically: throw `ValidationError`

### UC-COL-003: Reorder Collection Items

**Purpose**: Persist manual order for collection membership.

**Input**:
```
{
  collectionId: UserCollectionId
  orderedComicIds: List<ComicId>
}
```

**Main Flow**:
1. System validates collection exists
2. System validates the supplied comic IDs exactly match current membership with no duplicates or omissions
3. System updates all affected UserCollectionItem `sortIndex` values in one transaction
4. System sets or preserves `UserCollection.sortOrder = "manual"`
5. System emits `collection.reordered` event
6. Return ordered items

**Error Handling**:
- If collection not found: throw `NotFoundError`
- If membership list is incomplete or contains unknown comics: throw `ValidationError`

### UC-COL-003b: Move Collection Item

**Purpose**: Move one comic within a manual collection order without sending the full membership list.

**Input**:
```
{
  collectionId: UserCollectionId
  comicId: ComicId
  afterComicId: ComicId (optional; null/absent means move to start)
}
```

**Main Flow**:
1. System validates collection exists
2. System validates `comicId` is a current member of the collection
3. If `afterComicId` is provided, system validates it is a different current member of the same collection
4. System moves the item to the requested position and reassigns affected `sortIndex` values atomically
5. System sets or preserves `UserCollection.sortOrder = "manual"`
6. System emits `collection.item_moved` event
7. Return ordered items or the moved item plus its new neighbors

**Error Handling**:
- If collection or item not found: throw `NotFoundError`
- If `afterComicId` is unknown, belongs to another collection, or equals `comicId`: throw `ValidationError`

### UC-COL-004: List Collection Comics

**Purpose**: Read comics inside a collection using the collection's sort policy.

**Input**:
```
{
  collectionId: UserCollectionId
  includeRemoved: Boolean (optional, default false)
  limit: Integer (optional, default 100)
  offset: Integer (optional, default 0)
}
```

**Main Flow**:
1. System validates collection exists
2. System loads UserCollectionItems and joined Comics
3. Unless `includeRemoved = true`, filter comics whose `libraryStatus = "removed"`
4. Apply collection sort policy:
   - `manual`: `UserCollectionItem.sortIndex` ASC
   - `title`: current primary title ASC
   - `updated_at`: Comic/metadata update timestamp DESC
   - `last_read`: ReaderSession `updatedAt` DESC, unread last
5. Return paginated items and comics

**Error Handling**:
- If collection not found: throw `NotFoundError`

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
  event: DiagnosticsEvent (eventName: "favorite.marked")
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
  event: DiagnosticsEvent (eventName: "favorite.unmarked")
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
  chapterKind: String ("chapter" | "episode" | "oneshot" | "volume" | "season" | "group", optional, default "chapter")
}
```

**Main Flow**:
1. System retrieves ImportBatch and files
2. System validates `chapterKind`; page-bearing imports normally use `chapter`, `episode`, or `oneshot`
3. Based on `groupingStrategy`:
   - `single_chapter`: Create one chapter with all pages
   - `by_folder`: Create chapter per folder
   - `by_file`: Create chapter per file (archive or container)
4. Based on `chapterNumbering`:
   - `sequential`: normalized decimal strings such as `"1"`, `"2"`, `"3"`
   - `by_filename`: extract and normalize decimal strings such as `"1.5"`
5. For each page-bearing imported unit: create a Chapter with the requested `chapterKind` and create all pages in order
6. If import grouping creates container nodes (`volume`, `season`, or `group`), those nodes may own children but should not own readable Pages directly
7. Initialize chapter page ordering from the canonical source sequence
8. System emits `chapters.created` event
9. Return created Chapters

**Post-conditions**:
- Chapters created with sequential numbers
- Pages created in order
- Resolved page order defaults to the canonical source sequence (`pageIndex` ascending); implementation may satisfy this through synthetic fallback or explicit order-row materialization

**Error Handling**:
- If ImportBatch not found: throw `NotFoundError`
- If invalid strategy: throw `ValidationError`
- If invalid or structurally incompatible `chapterKind`: throw `ValidationError`
- If parsing fails: throw `ValidationError`

**Output**:
```
{
  chaptersCreated: Integer
  chapters: List<Chapter>
  pagesPerChapter: List<Integer>
  event: DiagnosticsEvent (eventName: "chapters.created")
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
  event: DiagnosticsEvent (eventName: "chapter.pages_reordered")
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
  includeRemoved: Boolean (optional, default false)
  limit: Integer (optional, default 50)
  offset: Integer (optional, default 0)
}
```

**Main Flow**:
1. System performs full-text search on `title`, `description`, `author`
2. Unless `includeRemoved = true`, system filters out comics with `libraryStatus = "removed"`
3. System orders results by relevance
4. System paginates results
5. For each comic: retrieve metadata and reader session
6. Return search results

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
  includeRemoved: Boolean (optional, default false)
  limit: Integer (optional, default 50)
  offset: Integer (optional, default 0)
}
```

**Main Flow**:
1. System retrieves Comics, excluding `libraryStatus = "removed"` unless `includeRemoved = true`
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

Use cases may emit `DiagnosticsEvent` through the diagnostics repository when configured. Diagnostics writes are best-effort evidence writes: failure to persist diagnostics must not fail or roll back the primary business use case. Current canonical persisted shape:

```
Entity: DiagnosticsEvent
  id: String (UUID v4)
  schemaVersion: String ("1.0.0")
  timestamp: Timestamp (UTC)
  level: String ("trace" | "info" | "warn" | "error")
  channel: String (e.g., "reader.route")
  eventName: String (e.g., "comic.created", "reader.position_changed")
  correlationId: String (optional trace ID)
  boundary: String (optional)
  authority: String (optional)
  comicId: String (optional)
  sourcePlatformId: String (optional)
  action: String (optional)
  payload: Object (event-specific data)
```

**DiagnosticsEvent Examples**:
```
{
  level: "info",
  channel: "comic",
  eventName: "comic.created",
  action: "created",
  comicId: "...",
  payload: { normalizedTitle }
}

{
  level: "info",
  channel: "reader.position",
  eventName: "reader.position_changed",
  action: "updated",
  comicId: "...",
  payload: { pageId, chapterId, pageIndex }
}
```

---

## Use Case Error Matrix

| Use Case | Status | NotFound | Duplicate | IdempotencyConflict | Validation | ReaderUnresolved | ReaderInvalidPos | Permission* | Storage |
|----------|--------|----------|-----------|---------------------|------------|-----------------|-----------------|-------------|---------|
| Create Comic | Implemented | - | - | X | X | - | - | - | X |
| Import Comic | Deferred/Legacy | X | X | - | X | - | - | - | X |
| Update Metadata | Implemented | X | - | - | X | - | - | - | X |
| Remove Comic | Planned Canonical | X | - | - | X | - | - | X | X |
| Permanently Delete Comic | Planned Canonical | X | - | - | X | - | - | X | X |
| Add SourceLink | Planned Canonical | X | X | - | X | - | - | - | X |
| Update SourceLink Status | Planned Canonical | X | - | - | X | - | - | - | X |
| Upsert ChapterSourceLink | Planned Canonical | X | - | - | X | - | - | - | X |
| Open Reader | Target | X | - | - | X | X | X | - | X |
| Update Position | Target | X | - | - | - | - | X | - | X |
| Get Position | Target | X | - | - | - | - | - | - | - |
| Clear Position | Planned Canonical | X | - | - | - | - | - | - | X |
| Create Collection | Planned Canonical | X | - | - | X | - | - | - | X |
| Add Collection Item | Planned Canonical | X | X | - | X | - | - | - | X |
| Reorder Collection | Planned Canonical | X | - | - | X | - | - | - | X |
| Move Collection Item | Planned Canonical | X | - | - | X | - | - | - | X |
| List Collection | Planned Canonical | X | - | - | - | - | - | - | X |
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
