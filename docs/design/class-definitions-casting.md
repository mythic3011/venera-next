# Class Definitions & Casting Rules

**Language-agnostic class hierarchy, data transformation patterns, and casting between layers.**

---

## Overview

Venera uses **strong typing** across all layers. Data must be cast/transformed at layer boundaries:

```
Presentation (ComicUI model)
    ↓ Cast to IPC
Protobuf Message (serialized)
    ↓ Cast to Domain
Domain Entity (Comic)
    ↓ Cast to Database
Database Row
```

Each cast validates the source data before returning the target type.

---

## Class Hierarchy

### Domain Layer: Entity Classes

All entities are **immutable** once created. Changes trigger new events, not mutations.

```
Aggregate Root: Comic
  ├─ Immutable: id, normalizedTitle, createdAt
  ├─ Mutable: metadata (ComicMetadata), favorite, readerSession
  └─ Invariants:
     - normalizedTitle is unique
     - all chapters belong to this comic

Aggregate Root: Chapter
  ├─ Immutable: id, comicId, createdAt
  ├─ Mutable: title, pages
  └─ Invariants:
     - chapterNumber is unique within comic
     - pages are contiguous (0, 1, 2, ...)

Entity: Page
  ├─ Immutable: id, chapterId, pageIndex, createdAt
  └─ Invariants:
     - pageIndex is 0-based within chapter
     - localCachePath may be null

Entity: ComicMetadata
  ├─ Owned by: Comic
  ├─ Mutable: title, description, coverLocalPath, authorName, genreTags
  └─ Invariants:
     - cannot exist without parent Comic

Entity: ReaderSession
  ├─ Immutable: id, comicId, createdAt
  ├─ Mutable: chapterId, pageIndex, activeTabPosition, updatedAt
  └─ Invariants:
     - one session per comic
     - position always valid (chapter exists, pageIndex < page count)

Entity: PageOrder
  ├─ Owned by: Chapter
  ├─ Mutable: orderType, userPagesOrder, updatedAt
  └─ Invariants:
     - one per chapter
     - orderType in [source, user_override, import_detected]

Entity: SourcePlatform
  ├─ Immutable: id, canonicalKey, kind, createdAt
  ├─ Mutable: displayName, isEnabled
  └─ Invariants:
     - canonicalKey is unique
     - kind in [local, remote, virtual]

Entity: SourceManifest
  ├─ Immutable: id, sourcePlatformId, version, createdAt
  └─ Invariants:
     - id is deterministic hash of content
     - validates against schemas/source_manifest.schema.json

Entity: Favorite
  ├─ Immutable: id, comicId, markedAt, createdAt
  ├─ Mutable: lastAccessedAt
  └─ Invariants:
     - one favorite per comic
     - markedAt is immutable

Entity: ImportBatch
  ├─ Immutable: id, sourceType, sourcePath, createdAt
  ├─ Mutable: completedAt, comicId
  └─ Invariants:
     - files list is immutable (ordered by index)
     - checksums prevent duplicates
```

### Application Layer: UseCase Request/Response Classes

Request/Response objects are **data transfer objects** (DTOs). Immutable after construction.

```
UseCase Request Classes:
  ├─ CreateComicRequest
  │   ├─ title: String (required)
  │   ├─ description: String (optional)
  │   ├─ authorName: String (optional)
  │   └─ genreTags: List<String> (optional)
  │
  ├─ UpdateComicMetadataRequest
  │   ├─ comicId: ComicId (required)
  │   ├─ title: String (optional)
  │   └─ ...
  │
  ├─ DeleteComicRequest
  │   ├─ comicId: ComicId (required)
  │   └─ confirmDeletion: Boolean (required)
  │
  ├─ UpdateReaderPositionRequest
  │   ├─ comicId: ComicId (required)
  │   ├─ chapterId: ChapterId (required)
  │   └─ pageIndex: Integer (required)
  │
  └─ ImportComicRequest
      ├─ sourceType: String (required)
      ├─ sourcePath: String (required)
      ├─ metadata: ImportMetadata (optional)
      ├─ groupingStrategy: String (optional)
      └─ chapterNumbering: String (optional)

UseCase Response Classes:
  ├─ CreateComicResponse
  │   ├─ comic: Comic
  │   └─ event: DiagnosticsEvent
  │
  ├─ GetComicResponse
  │   ├─ comic: Comic
  │   └─ session: ReaderSession
  │
  ├─ UpdateReaderPositionResponse
  │   ├─ session: ReaderSession
  │   ├─ isFavorited: Boolean
  │   └─ event: DiagnosticsEvent
  │
  └─ ListComicsResponse
      ├─ comics: List<Comic>
      ├─ totalCount: Integer
      ├─ limit: Integer
      └─ offset: Integer
```

### Presentation Layer: UI Model Classes

UI models are specific to Dart/Flutter. **Never share domain entities** with UI.

```
Presentation (UI Model) Classes:
  ├─ ComicListViewModel
  │   ├─ comics: List<ComicUI>
  │   ├─ isLoading: Boolean
  │   ├─ error: String
  │   ├─ sortBy: String
  │   └─ functions:
  │       ├─ loadComics()
  │       ├─ searchComics(query)
  │       ├─ onComicTap(comicId)
  │
  ├─ ComicDetailViewModel
  │   ├─ comic: ComicUI
  │   ├─ chapters: List<ChapterUI>
  │   ├─ isFavorited: Boolean
  │   ├─ functions:
  │       ├─ markFavorite()
  │       ├─ unmarkFavorite()
  │       ├─ openChapter(chapterId)
  │
  ├─ ReaderViewModel
  │   ├─ comic: ComicUI
  │   ├─ chapter: ChapterUI
  │   ├─ currentPage: PageUI
  │   ├─ totalPages: Integer
  │   ├─ functions:
  │       ├─ nextPage()
  │       ├─ previousPage()
  │       ├─ goToPage(index)
  │       ├─ nextChapter()
  │
  ├─ ComicUI (UI-specific Comic representation)
  │   ├─ id: String (UUID)
  │   ├─ title: String
  │   ├─ coverImage: Image (cached)
  │   ├─ chapterCount: Integer
  │   ├─ isFavorited: Boolean
  │   ├─ lastRead: DateTime (nullable)
  │
  └─ ImportProgressViewModel
      ├─ importBatchId: String
      ├─ sourceType: String
      ├─ pagesProcessed: Integer
      ├─ pagesTotal: Integer
      ├─ progress: Double (0.0-1.0)
      ├─ status: String
      └─ functions:
          ├─ cancel()
          ├─ retry()
```

### Infrastructure Layer: Database Model Classes

Database models map directly to table schemas. **Only in Infrastructure layer**.

```
Database (Row) Classes:
  ├─ ComicRow
  │   ├─ id: String (UUID)
  │   ├─ normalized_title: String
  │   ├─ created_at: String (ISO8601)
  │   ├─ updated_at: String (ISO8601)
  │
  ├─ ComicMetadataRow
  │   ├─ comic_id: String (FK)
  │   ├─ title: String
  │   ├─ description: String (nullable)
  │   ├─ cover_local_path: String (nullable)
  │   ├─ author_name: String (nullable)
  │   └─ genre_tags: String (JSON array)
  │
  ├─ ChapterRow
  │   ├─ id: String (UUID)
  │   ├─ comic_id: String (FK)
  │   ├─ chapter_number: Float
  │   ├─ title: String (nullable)
  │   ├─ source_platform_id: String (FK, nullable)
  │   ├─ source_chapter_id: String (nullable)
  │   ├─ created_at: String
  │   ├─ updated_at: String
  │
  └─ PageRow
      ├─ id: String (UUID)
      ├─ chapter_id: String (FK)
      ├─ page_index: Integer
      ├─ source_platform_id: String (FK, nullable)
      ├─ source_page_id: String (nullable)
      ├─ local_cache_path: String (nullable)
      ├─ created_at: String
      └─ updated_at: String
```

---

## Casting & Transformation Rules

### Rule 1: Presentation → IPC Message

**When**: User action triggers API call

**Cast**: ComicUI (Presentation) → CreateComicRequest (IPC protobuf)

```
Presentation Layer (ComicUI):
  {
    id: "abc123",
    title: "My Comic",
    coverImage: Image(...)  // ← CANNOT CROSS BOUNDARY
  }
    ↓ (Extract relevant fields, serialize cover to file)
IPC Message (CreateComicRequest):
  {
    title: "My Comic",
    description: null,
    author_name: null,
    genre_tags: []
  }
    ↓ (Serialize to protobuf bytes)
Transmission (TLS encrypted)
```

**Validation at Presentation**:
- ✓ title is non-empty
- ✓ title length < 500 chars
- ✓ coverImage is valid image (if provided)
- ✗ Never send: Image objects, UI state, widgets

**Transformation Code Pattern**:
```
function toProtobufMessage(comicUI: ComicUI) -> CreateComicRequest:
  request = CreateComicRequest()
  request.title = comicUI.title  // Direct copy
  request.description = comicUI.description  // Can be null
  // Don't copy: coverImage, isLoading, isFavorited
  return request
```

---

### Rule 2: IPC Message → Domain Entity

**When**: Application layer receives IPC message

**Cast**: CreateComicRequest (IPC protobuf) → Comic (Domain entity)

```
IPC Message (CreateComicRequest):
  {
    title: "My Comic",
    description: "A great comic",
    author_name: null,
    genre_tags: []
  }
    ↓ (Validate against domain rules)
Validation:
  - Title not empty ✓
  - Title not duplicate ✓
  - Author name valid (if provided) ✓
    ↓ (Construct domain entity)
Domain Entity (Comic):
  Comic {
    id: UUID.generate(),
    normalized_title: "my comic",  // Normalized
    title: "My Comic",
    description: "A great comic",
    author_name: null,
    created_at: now(),
    updated_at: now()
  }
```

**Validation at Application**:
- ✓ title matches domain rules (not empty, not duplicate)
- ✓ description length reasonable
- ✓ genre_tags count < 100
- ✗ Never pass: IPC-level errors (serialization errors caught before this)

**Transformation Code Pattern**:
```
function fromProtobufMessage(request: CreateComicRequest) -> Comic | Error:
  // Input validation
  if request.title.isEmpty():
    throw ValidationError("title_required")
  
  // Domain rule check
  normalizedTitle = normalizeTitle(request.title)
  existing = comicRepository.getComicByNormalizedTitle(normalizedTitle)
  if existing != null:
    throw DuplicateError("comic_title_exists")
  
  // Construct domain entity
  comic = Comic {
    id: Uuid.generate(),
    normalized_title: normalizedTitle,
    title: request.title,
    description: request.description,
    author_name: request.author_name,
    created_at: now(),
    updated_at: now()
  }
  
  return comic
```

---

### Rule 3: Domain Entity → Database Row

**When**: Repository persists entity

**Cast**: Comic (Domain entity) → ComicRow (Database row)

```
Domain Entity (Comic):
  Comic {
    id: "abc123-uuid",
    normalized_title: "my comic",
    title: "My Comic",
    description: "A great comic",
    author_name: null,
    created_at: "2026-05-05T10:30:00Z",
    updated_at: "2026-05-05T10:30:00Z",
    metadata: ComicMetadata { ... }  // Separate entity
  }
    ↓ (Validate all fields)
    ↓ (Extract metadata to separate row)
Database Rows:
  ComicRow:
    {
      id: "abc123-uuid",
      normalized_title: "my comic",
      created_at: "2026-05-05T10:30:00Z",
      updated_at: "2026-05-05T10:30:00Z"
    }
  
  ComicMetadataRow:
    {
      comic_id: "abc123-uuid",
      title: "My Comic",
      description: "A great comic",
      author_name: null,
      ...
    }
    ↓ (SQL INSERT)
Database
```

**Validation at Ports/Infrastructure**:
- ✓ id is valid UUID
- ✓ normalized_title matches domain rules
- ✓ timestamps are ISO8601
- ✓ All NOT NULL fields populated
- ✗ Never pass: Domain aggregates directly (must flatten to rows)

**Transformation Code Pattern**:
```
function toComicRow(comic: Comic) -> (ComicRow, ComicMetadataRow) | Error:
  // Validate domain entity
  if comic.id == null:
    throw ValidationError("id_required")
  if comic.normalized_title.isEmpty():
    throw ValidationError("normalized_title_required")
  
  // Create database rows (flatten aggregate)
  comicRow = ComicRow {
    id: comic.id,
    normalized_title: comic.normalized_title,
    created_at: comic.created_at,
    updated_at: comic.updated_at
  }
  
  metadataRow = ComicMetadataRow {
    comic_id: comic.id,
    title: comic.metadata.title,
    description: comic.metadata.description,
    ...
  }
  
  return (comicRow, metadataRow)
```

---

### Rule 4: Database Row → Domain Entity

**When**: Repository returns query results

**Cast**: ComicRow + ComicMetadataRow (Database rows) → Comic (Domain entity)

```
Database Rows:
  ComicRow:
    {
      id: "abc123-uuid",
      normalized_title: "my comic",
      created_at: "2026-05-05T10:30:00Z",
      updated_at: "2026-05-05T10:30:00Z"
    }
  
  ComicMetadataRow:
    {
      comic_id: "abc123-uuid",
      title: "My Comic",
      description: "A great comic",
      author_name: null,
      ...
    }
    ↓ (Validate row format)
    ↓ (Join rows into aggregate)
Domain Entity (Comic):
  Comic {
    id: "abc123-uuid",
    normalized_title: "my comic",
    title: "My Comic",
    description: "A great comic",
    metadata: ComicMetadata { ... }
  }
```

**Validation at Infrastructure**:
- ✓ Row matches schema (all columns present)
- ✓ id is valid UUID
- ✓ Timestamps are valid ISO8601
- ✓ Foreign keys reference existing rows (integrity)
- ✗ Never return: Raw database values (must construct entities)

**Transformation Code Pattern**:
```
function fromComicRow(comicRow: ComicRow, metadataRow: ComicMetadataRow) -> Comic | Error:
  // Validate row format
  if comicRow == null:
    throw NotFoundError("comic_row_not_found")
  
  // Parse timestamps
  createdAt = parseTimestamp(comicRow.created_at)
  if createdAt == null:
    throw ValidationError("invalid_created_at_format")
  
  // Construct metadata entity
  metadata = ComicMetadata {
    comic_id: comicRow.id,
    title: metadataRow.title,
    description: metadataRow.description,
    ...
  }
  
  // Construct domain entity
  comic = Comic {
    id: comicRow.id,
    normalized_title: comicRow.normalized_title,
    metadata: metadata,
    created_at: createdAt,
    updated_at: parseTimestamp(comicRow.updated_at)
  }
  
  return comic
```

---

### Rule 5: Domain Entity → IPC Response

**When**: Application returns response to Presentation

**Cast**: Comic (Domain entity) → ComicUI (via protobuf)

```
Domain Entity (Comic):
  Comic {
    id: "abc123-uuid",
    normalized_title: "my comic",
    title: "My Comic",
    description: "A great comic",
    author_name: null,
    chapters: List<Chapter> (20 items),
    favorite: Favorite (if marked)
  }
    ↓ (Select fields for IPC)
IPC Message (Comic proto):
  {
    id: "abc123-uuid",
    normalized_title: "my comic",
    title: "My Comic",
    description: "A great comic",
    author_name: null,
    chapter_count: 20,  // Derived, not transferred
    page_count: 300,    // Derived, not transferred
    is_favorited: true,  // Derived from favorite
    created_at: "2026-05-05T10:30:00Z",
    updated_at: "2026-05-05T10:30:00Z"
  }
    ↓ (Serialize to protobuf bytes)
Transmission
    ↓ (Deserialize at Presentation)
Presentation (ComicUI):
  ComicUI {
    id: "abc123-uuid",
    title: "My Comic",
    coverImage: null,  // Load separately if needed
    chapterCount: 20,
    isFavorited: true,
    lastRead: null  // Calculate from ReaderSession
  }
```

**Transformation Code Pattern**:
```
function toProtobufComic(comic: Comic, readerSession: ReaderSession) -> Comic (proto):
  protoComic = Comic()
  protoComic.id = comic.id
  protoComic.title = comic.title
  protoComic.description = comic.description
  protoComic.author_name = comic.authorName
  protoComic.genre_tags = comic.genreTags
  
  // Derive fields
  protoComic.chapter_count = comic.chapters.length
  protoComic.page_count = comic.chapters.map(c => c.pages.length).sum()
  protoComic.is_favorited = comic.favorite != null
  
  // Include reader session
  if readerSession != null:
    protoComic.reader_position = ReaderPosition {
      chapter_id: readerSession.chapterId,
      page_index: readerSession.pageIndex
    }
  
  return protoComic
```

---

### Rule 6: IPC Response → Presentation Model

**When**: Presentation receives IPC response

**Cast**: Protobuf Comic message → ComicUI (UI model)

```
IPC Message (Comic proto):
  {
    id: "abc123-uuid",
    title: "My Comic",
    chapter_count: 20,
    is_favorited: true,
    reader_position: {
      chapter_id: "ch123",
      page_index: 5
    }
  }
    ↓ (Deserialize from protobuf)
    ↓ (Load additional UI state)
Presentation (ComicUI):
  ComicUI {
    id: "abc123-uuid",
    title: "My Comic",
    chapterCount: 20,
    isFavorited: true,
    lastRead: "2 days ago",  // Calculate from timestamp
    coverImage: null,  // Load asynchronously
    isLoading: false
  }
```

**Transformation Code Pattern**:
```
function fromProtobufComic(protoComic: Comic) -> ComicUI:
  comicUI = ComicUI(
    id: protoComic.id,
    title: protoComic.title,
    chapterCount: protoComic.chapter_count,
    isFavorited: protoComic.is_favorited
  )
  
  // Calculate UI-specific fields
  if protoComic.reader_position != null:
    lastReadTime = calculateLastRead(protoComic.reader_position)
    comicUI.lastRead = formatTimeAgo(lastReadTime)
  
  // Load cover asynchronously (don't block UI)
  loadCoverImage(protoComic.id)
    .then(image => comicUI.coverImage = image)
    .catch(error => log("Cover load failed: $error"))
  
  return comicUI
```

---

## Casting Patterns

### Pattern: Optional Field Propagation

```
When a field is optional (nullable) at source, handle at each layer:

Domain:
  Comic.metadata.description: String | null

→ IPC:
  repeated string genre_tags: (if null → empty array)

→ Presentation:
  ComicUI.descriptionText: String (empty string if null)

Pattern:
  if source.field == null:
    target.field = defaultValue()  // "" for string, 0 for int, [] for array
  else:
    target.field = source.field
```

### Pattern: Computed Field Derivation

```
Some fields are computed, not stored:

Domain (Comic):
  chapters: List<Chapter>
  
IPC (proto):
  chapter_count: int (derived: chapters.length)
  
Presentation (ComicUI):
  chapterCount: int (echoed from IPC)

Pattern:
  Never send full chapters list across IPC (too large)
  Instead send: count, summary, or paginated
  Calculate derived fields at each layer
```

### Pattern: Error Transformation

```
Infrastructure error:
  SqliteError("UNIQUE constraint failed: comics.normalized_title")
  
→ Ports layer transforms:
  DuplicateError("comic_title_exists", "Comic title already exists")
  
→ Application layer transforms:
  DuplicateError("comic_title_exists")
  
→ IPC response:
  {
    success: false,
    error: {
      error_code: "DUPLICATE",
      message: "Comic title already exists"
    }
  }
  
→ Presentation layer:
  Toast.show("A comic with this title already exists")

Pattern:
  Each layer transforms lower-level errors to its abstraction
  Never expose: SQL, file paths, stack traces
```

### Pattern: Collection Pagination

```
Domain (getComicsFromRepository):
  Return all comics that match criteria (possibly large list)

Ports (repository interface):
  listComics(limit: int, offset: int) -> List<Comic>
  Return paginated slice, not full list

IPC (proto):
  message ListComicsResponse {
    repeated Comic comics = 1;
    int32 total_count = 2;      // Total available, not size
    int32 limit = 3;            // Echoed
    int32 offset = 4;           // Echoed
  }

Presentation:
  Display paginated list with "load more" button
  Calculate next offset: offset + limit

Pattern:
  Large collections paginated at Ports layer
  Never send: full list across IPC
  Always send: total_count, limit, offset for pagination
```

---

## Cross-Layer Data Flow Examples

### Example 1: Create Comic Workflow

```
[PRESENTATION]
  ComicUI input: { title: "New Comic" }
    ↓ toProtobufMessage()
[IPC] CreateComicRequest protobuf
    ↓ HTTP/gRPC
[APPLICATION]
  Deserialize IPC → CreateComicRequest
    ↓ validate input (title not empty)
    ↓ normalize title
    ↓ fromProtobufMessage()
  Domain Entity: Comic
    ↓ comicRepository.createComic()
[PORTS]
  Validate entity (all fields valid)
    ↓ toComicRow()
  Database Row: ComicRow, ComicMetadataRow
[INFRASTRUCTURE]
  SQL INSERT comic
  SQL INSERT comic_metadata
[DATABASE]
  Two rows created
    ↓ return rows
[INFRASTRUCTURE]
  fromComicRow() → Comic entity
[PORTS]
  Validate returned entity
    ↓ return Comic
[APPLICATION]
  Emit event: comic.created
    ↓ toProtobufComic()
  IPC: Comic message
    ↓ HTTP/gRPC
[PRESENTATION]
  Deserialize IPC → ComicUI
  Add to list
  Show success toast
```

### Example 2: Read Comic (Update Position) Workflow

```
[PRESENTATION]
  User taps page 10 on chapter 2
    ↓ toProtobufMessage()
[IPC] UpdateReaderPositionRequest { comic_id, chapter_id, page_index }
    ↓ HTTP/gRPC
[APPLICATION]
  Deserialize IPC
    ↓ validate chapter exists in comic
    ↓ validate page_index valid
    ↓ fromProtobufMessage()
  Domain Entity: ReaderSession (updated)
    ↓ readerSessionRepository.updatePosition()
[PORTS]
  Validate position (chapter in comic, page exists)
    ↓ toReaderSessionRow()
  Database Row: ReaderSessionRow
[INFRASTRUCTURE]
  SQL UPDATE reader_session
  if favorite: SQL UPDATE favorite.last_accessed_at
[DATABASE]
  One row updated
    ↓ return row
[INFRASTRUCTURE]
  fromReaderSessionRow() → ReaderSession
[PORTS]
  Validate returned entity
    ↓ return ReaderSession
[APPLICATION]
  Emit event: reader.position_changed
    ↓ toProtobufMessage()
  IPC: UpdateReaderPositionResponse
    ↓ HTTP/gRPC
[PRESENTATION]
  Deserialize IPC → Update UI state
  Render page 10
```

---

## Type Safety Contract

Each transformation includes:

1. **Input Type**: What we receive
2. **Validation**: What rules apply
3. **Output Type**: What we return
4. **Errors**: What can go wrong
5. **Side Effects**: What happens (logs, events, DB changes)

```
Function: createComic(request: CreateComicRequest) -> CreateComicResponse | Error

Input Type: CreateComicRequest
  {
    title: String,
    description: String | null,
    author_name: String | null,
    genre_tags: Array<String>
  }

Validation:
  - title non-empty ✓
  - title.length < 500 ✓
  - title not duplicate (query DB) ✓
  - genre_tags.length < 100 ✓

Output Type: CreateComicResponse
  {
    comic: Comic (domain entity),
    event: DiagnosticsEvent
  }

Errors:
  - ValidationError (title empty)
  - DuplicateError (title exists)
  - StorageError (DB fails)

Side Effects:
  - INSERT into comics table
  - INSERT into comic_metadata table
  - INSERT into reader_sessions table (default)
  - EMIT diagnostics_event
  - LOG event to audit trail
```

---

## Implementation Checklist

For each casting rule, implement:

- [ ] **Validation function**: Check source data before casting
- [ ] **Transform function**: Map source → target type
- [ ] **Error handler**: Catch and transform errors
- [ ] **Logger**: Log transformation (no sensitive data)
- [ ] **Tests**: Unit tests for validation + transformation
- [ ] **Documentation**: Document assumptions and invariants

