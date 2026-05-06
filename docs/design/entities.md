# Entities Specification

**Language-agnostic entity definitions for Venera canonical runtime.**

---

## Entity Catalog

### 1. Comic
**Purpose**: Canonical identity for a comic work.

```
Entity: Comic
  id: ComicId (UUID v4)
  normalizedTitle: String (lowercase, no punctuation, for deduplication)
  createdAt: Timestamp
  updatedAt: Timestamp
```

**Invariants**:
- `id` is immutable
- `normalizedTitle` is normalized once at creation
- `normalizedTitle` is used for deduplication (two comics cannot share same normalized title)
- `updatedAt` >= `createdAt`

**Relationships**:
- Owns: Chapter (1:N)
- Owns: Metadata (1:1, optional)
- Owns: Favorite (1:1, optional)

---

### 2. ComicMetadata
**Purpose**: Mutable properties of a comic (separate from identity).

```
Entity: ComicMetadata
  comicId: ComicId (foreign key, immutable)
  title: String (user-facing, may contain punctuation)
  description: String (optional, long text)
  coverLocalPath: String (optional, file path to cached cover)
  authorName: String (optional)
  genreTags: List<String> (optional)
```

**Invariants**:
- `comicId` is immutable
- Cannot exist without parent Comic
- All fields mutable

---

### 3. Chapter
**Purpose**: Ordered sequence of pages within a comic.

```
Entity: Chapter
  id: ChapterId (UUID v4)
  comicId: ComicId (foreign key, immutable)
  chapterNumber: Float (canonical order, e.g., 1.0, 1.5, 2.0)
  title: String (optional, chapter name)
  sourcePlatformId: SourcePlatformId (optional, link to source platform)
  sourceChapterId: String (optional, source-specific identifier)
  createdAt: Timestamp
  updatedAt: Timestamp
```

**Invariants**:
- `id` is immutable
- `comicId` is immutable
- `chapterNumber` is unique within comic (no two chapters have same number)
- `chapterNumber` is positive
- `chapterNumber` defines sort order (pages ordered by chapterNumber ascending)
- Cannot exist without parent Comic

**Relationships**:
- Parent: Comic (N:1)
- Owns: Page (1:N)
- Owns: PageOrder (1:1)

---

### 4. Page
**Purpose**: Ordered image within a chapter.

```
Entity: Page
  id: PageId (UUID v4)
  chapterId: ChapterId (foreign key, immutable)
  pageIndex: Integer (0-based, canonical order within chapter)
  sourcePlatformId: SourcePlatformId (optional, link to source platform)
  sourcePageId: String (optional, source-specific identifier)
  localCachePath: String (optional, file path to cached image)
  createdAt: Timestamp
  updatedAt: Timestamp
```

**Invariants**:
- `id` is immutable
- `chapterId` is immutable
- `pageIndex` is unique within chapter (no two pages have same index)
- `pageIndex` is 0-based
- `pageIndex` is contiguous (no gaps: if chapter has 5 pages, indices are 0,1,2,3,4)
- Cannot exist without parent Chapter

**Relationships**:
- Parent: Chapter (N:1)

---

### 5. PageOrder
**Purpose**: Policy for page ordering within a chapter (source vs. user override vs. import detected).

```
Entity: PageOrder
  id: String (UUID v4)
  chapterId: ChapterId (foreign key, immutable)
  pageCount: Integer (count of pages in chapter at time of creation)
  orderType: Enum (source | user_override | import_detected)
  userPagesOrder: String (optional, delimited list of page IDs if user override)
  createdAt: Timestamp
  updatedAt: Timestamp
```

**Invariants**:
- One PageOrder per Chapter
- If `orderType` is `source`, pages are in source order
- If `orderType` is `user_override`, `userPagesOrder` contains space/comma-delimited page IDs
- If `orderType` is `import_detected`, pages are in import-detected order
- `pageCount` is informational (for audit trail)

---

### 6. ReaderSession
**Purpose**: Canonical normalized reader position state.

```
Entity: ReaderSession
  id: ReaderSessionId (UUID v4)
  comicId: ComicId (foreign key, immutable)
  chapterId: ChapterId (foreign key, immutable)
  pageIndex: Integer (0-based canonical position, immutable except updates)
  activeTabPosition: Integer (reserved, for future multi-tab, default 0)
  createdAt: Timestamp
  updatedAt: Timestamp
```

**Invariants**:
- `id` is immutable
- `comicId` is immutable
- Position (chapter + page) is normalized in database (not JSON)
- One ReaderSession per Comic (updated, not created)
- `updatedAt` reflects latest position change
- All position state is explicit (no JSON blobs)

---

### 7. SourcePlatform
**Purpose**: Provider of comics (local, remote, virtual).

```
Entity: SourcePlatform
  id: SourcePlatformId (UUID v4)
  canonicalKey: String (stable identifier, e.g., "copymanga", "local")
  displayName: String (user-facing name)
  kind: Enum (local | remote | virtual)
  status: Enum (active | disabled | deprecated)
  createdAt: Timestamp
  updatedAt: Timestamp
```

**Invariants**:
- `id` is immutable
- `canonicalKey` is unique and immutable (stable across sessions)
- `kind` is immutable
- `status` is mutable but constrained to `active | disabled | deprecated`

---

### 8. SourceManifest
**Purpose**: Provider-specific behavior manifest (loaded from JSON, validated).

```
Entity: SourceManifest
  id: String (deterministic hash of manifest content)
  sourcePlatformId: SourcePlatformId (foreign key)
  version: String (semver)
  provider: String (name matching SourcePlatform)
  displayName: String
  baseUrl: String (endpoint base URL)
  headers: Map<String, String> (static headers, no auth tokens)
  search: Object (search endpoint configuration)
  comicDetail: Object (comic detail endpoint configuration)
  chapterList: Object (chapter listing configuration)
  pageList: Object (page listing configuration)
  imageUrl: Object (image URL transformation rules)
  permissions: List<String> (required permissions: e.g., ["network.http", "storage.cache"])
  runtimeVersion: String (minimum required runtime version, optional)
  createdAt: Timestamp
```

**Invariants**:
- Validated against canonical repository/package manifest contract
- No auth tokens or secrets in headers
- Permissions explicitly declared
- Immutable (new version = new manifest ID)

---

### 9. Favorite
**Purpose**: User's marked work.

```
Entity: Favorite
  id: FavoriteId (UUID v4)
  comicId: ComicId (foreign key, immutable)
  markedAt: Timestamp
  lastAccessedAt: Timestamp (optional)
```

**Invariants**:
- One Favorite per Comic
- `comicId` is immutable
- `markedAt` is immutable
- `lastAccessedAt` is updated on reader access

---

### 10. ImportBatch
**Purpose**: Metadata for file imports (CBZ, PDF, directories).

```
Entity: ImportBatch
  id: ImportBatchId (UUID v4)
  sourceType: Enum (cbz | pdf | directory)
  sourcePath: String (path to import source)
  files: List<ImportFile> (ordered files in batch)
  metadata: Object (import-specific metadata)
  comicId: ComicId (optional, assigned after import completes)
  createdAt: Timestamp
  completedAt: Timestamp (optional)
```

**Sub-Entity: ImportFile**
```
  path: String (relative path within batch)
  fileType: Enum (image | container | document)
  index: Integer (canonical order in import)
  checksum: String (SHA256 of file content)
  sizeBytes: Integer
```

**Invariants**:
- Files stored in canonical order (index is immutable)
- Checksums prevent deduplication errors
- One ImportBatch may import into one Comic

---

## ID System

### ID Types
All IDs are **UUIDs v4** (Universally Unique Identifiers, version 4):

```
ComicId           = UUID v4
ChapterId         = UUID v4
PageId            = UUID v4
ReaderSessionId   = UUID v4
SourcePlatformId  = UUID v4
ImportBatchId     = UUID v4
FavoriteId        = UUID v4
CorrelationId     = String (UUID v4 format, used for tracing)
```

### ID Ownership
- **ComicId**: Assigned by system at Comic creation
- **ChapterId**: Assigned by system at Chapter creation
- **PageId**: Assigned by system at Page creation
- **ReaderSessionId**: Assigned by system at ReaderSession creation
- **SourcePlatformId**: Assigned by system at SourcePlatform creation
- **ImportBatchId**: Assigned by system at ImportBatch creation
- **FavoriteId**: Assigned by system at Favorite creation

### ID Serialization
- All IDs serialized as UUID strings (RFC 4122 format)
- IDs are projections for external consumption
- Database stores IDs as native UUID types (if supported) or strings

---

## Relationships Diagram

```
Comic (1) ──→ (N) Chapter
  ├─→ ComicMetadata (1:1, optional)
  ├─→ Favorite (1:1, optional)
  └─→ ReaderSession (1:1)

Chapter (1) ──→ (N) Page
  └─→ PageOrder (1:1)

Page (N) ←─── (1) SourcePlatform (optional link)

SourcePlatform (1) ──→ (N) SourceManifest

ImportBatch ──→ Comic (optional, after completion)
```

---

## Validation Rules

### Comic
- `normalizedTitle` must be unique
- `id` must be valid UUID v4
- Both timestamps must be ISO8601

### Chapter
- `chapterNumber` must be unique within comic
- `chapterNumber` > 0
- `comicId` must reference existing Comic
- `id` must be valid UUID v4

### Page
- `pageIndex` must be unique and contiguous within chapter
- `pageIndex` >= 0
- `chapterId` must reference existing Chapter
- `id` must be valid UUID v4

### ReaderSession
- `comicId` must reference existing Comic
- `chapterId` must reference existing Chapter
- `pageIndex` must be < page count in chapter
- One ReaderSession per Comic

### SourcePlatform
- `canonicalKey` must be unique
- `kind` must be one of: local, remote, virtual
- `status` must be one of: active, disabled, deprecated
- `id` must be valid UUID v4

### SourceManifest
- Must validate against canonical repository/package manifest contract
- No secrets in headers
- Permissions must be declared

### Favorite
- `comicId` must reference existing Comic
- One Favorite per Comic
- `id` must be valid UUID v4

### ImportBatch
- Files must be ordered by index
- All checksums must be SHA256 format
- One ImportBatch completes to one Comic
