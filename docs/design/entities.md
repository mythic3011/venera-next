# Entities Specification

**Language-agnostic entity definitions for Venera canonical runtime.**

---

## Entity Catalog

### 1. Comic
**Purpose**: Canonical identity for a comic work.

```
Entity: Comic
  id: ComicId (UUID v4)
  normalizedTitle: String (lowercase, normalized matching/search signal)
  createdAt: Timestamp
  updatedAt: Timestamp
```

**Invariants**:
- `id` is immutable
- `normalizedTitle` is normalized once at creation
- `normalizedTitle` is a non-unique matching/search signal only
- `normalizedTitle` must never decide canonical comic identity by itself
- Multiple comics may share the same `normalizedTitle`
- `updatedAt` >= `createdAt`

**Relationships**:
- Owns: Chapter (1:N)
- Owns: Metadata (1:1, optional)
- Owns: Favorite (1:1, optional)
- Owns: ComicTitle (1:N)
- Owns: ReaderSession (1:1)

---

### 2. ComicMetadata
**Purpose**: Mutable properties of a comic (separate from identity).

```
Entity: ComicMetadata
  comicId: ComicId (foreign key, immutable)
  title: String (user-facing, may contain punctuation)
  description: String (optional, long text)
  coverStorageObjectId: String (optional, storage object reference)
  authorName: String (optional)
  tags: List<TagReference> (optional, read-model projection only)
```

**Invariants**:
- `comicId` is immutable
- Cannot exist without parent Comic
- All fields mutable
- `tags` is read/projection shape only, not canonical tag storage authority

**Sub-Entity: TagReference**
```
  canonicalKey: String (canonical taxonomy key)
  namespace: String
  facet: String
  valueType: String
  localizedLabel: String (optional)
  providerKey: String (optional, remote provenance)
  providerRawValue: String (optional, remote provenance)
```

---

### 3. ComicTitle
**Purpose**: Canonical title record surface separating primary and provenance title evidence.

```
Entity: ComicTitle
  id: String (UUID v4 or deterministic key)
  comicId: ComicId
  title: String
  normalizedTitle: String (non-unique matching signal)
  titleType: Enum (primary | source | alias)
  sourcePlatformId: SourcePlatformId (optional provenance reference)
  createdAt: Timestamp
```

**Invariants**:
- Title records are evidence/projection surfaces, not canonical comic identity by themselves
- `normalizedTitle` remains non-unique
- Primary title uniqueness is scoped to one active primary title per comic

---

### 4. Chapter
**Purpose**: Ordered sequence of pages within a comic.

```
Entity: Chapter
  id: ChapterId (UUID v4)
  comicId: ComicId (foreign key, immutable)
  chapterNumber: Float (optional ordering hint, e.g., 1.0, 1.5, 2.0)
  title: String (optional, chapter name)
  createdAt: Timestamp
  updatedAt: Timestamp
```

**Invariants**:
- `id` is immutable
- `comicId` is immutable
- `chapterNumber`, when present, is positive
- `chapterNumber` is an ordering hint, not chapter identity authority
- Canonical ordering may combine `chapterNumber` with fallback policy (for example `createdAt`/`id` or explicit order policy)
- Cannot exist without parent Comic

**Relationships**:
- Parent: Comic (N:1)
- Owns: Page (1:N)
- Owns: PageOrder (1:N)
- May have: ChapterSourceLink (1:N provenance edges)

---

### 5. Page
**Purpose**: Ordered image within a chapter.

```
Entity: Page
  id: PageId (UUID v4)
  chapterId: ChapterId (foreign key, immutable)
  pageIndex: Integer (0-based source/insertion index within chapter)
  storageObjectId: String (optional, storage object reference)
  createdAt: Timestamp
  updatedAt: Timestamp
```

**Invariants**:
- `id` is immutable
- `chapterId` is immutable
- `pageIndex` is unique within chapter (no two pages have same index)
- `pageIndex` is 0-based
- `pageIndex` is contiguous (no gaps: if chapter has 5 pages, indices are 0,1,2,3,4)
- Effective display order is governed by active `PageOrder`/`PageOrderItem` policy
- Cannot exist without parent Chapter

**Relationships**:
- Parent: Chapter (N:1)
- May have: PageSourceLink (1:N provenance edges)

---

### 6. ComicSourceLink
**Purpose**: Comic-level source provenance edge.

```
Entity: ComicSourceLink
  id: String (UUID v4)
  comicId: ComicId
  sourcePlatformId: SourcePlatformId
  sourceComicId: String
  linkStatus: Enum (active | inactive | stale)
  isPrimary: Boolean
  sourceUrl: String (optional, sanitized source URL)
  sourceTitle: String (optional)
  metadata: Object (optional, sanitized source metadata)
  linkedAt: Timestamp
  updatedAt: Timestamp
```

**Invariants**:
- Canonical comic identity remains owned by `Comic`, not this provenance edge
- Source identifiers are provenance evidence, not canonical comic identity by themselves

---

### 7. ChapterSourceLink
**Purpose**: Chapter-level source provenance edge.

```
Entity: ChapterSourceLink
  id: String (UUID v4)
  chapterId: ChapterId
  comicSourceLinkId: String
  sourceChapterId: String
  sourceGroupName: String (optional)
  sourceTitle: String (optional)
  sourceOrder: Integer (optional)
  sourceUrl: String (optional, sanitized source URL)
  metadata: Object (optional, sanitized source metadata)
  linkedAt: Timestamp
  updatedAt: Timestamp
```

**Invariants**:
- Canonical chapter identity remains owned by `Chapter`
- Grouped/flat source chapter structures are provenance and require explicit mapping to canonical chapter rows

---

### 8. PageSourceLink
**Purpose**: Page-level source provenance edge.

```
Entity: PageSourceLink
  id: String (UUID v4)
  pageId: PageId
  comicSourceLinkId: String
  chapterSourceLinkId: String (optional)
  sourcePageId: String
  sourceUrl: String (optional, sanitized source URL)
  metadata: Object (optional, sanitized source metadata)
  linkedAt: Timestamp
  updatedAt: Timestamp
```

**Invariants**:
- Canonical page identity remains owned by `Page`
- Raw source page references must not become canonical DB identity

---

### 9. PageOrder
**Purpose**: Named page-order profile for a chapter.

```
Entity: PageOrder
  id: String (UUID v4)
  chapterId: ChapterId (foreign key, immutable)
  orderName: String
  normalizedOrderName: String
  orderType: Enum (source | user_override | import_detected)
  isActive: Boolean
  createdAt: Timestamp
  updatedAt: Timestamp
```

**Invariants**:
- Multiple PageOrder profiles may exist per chapter
- Item-level order/hide semantics are expressed by `PageOrderItem`, not delimited text blobs
- At most one active PageOrder should exist per chapter

---

### 10. PageOrderItem
**Purpose**: Item-level ordering and visibility for a PageOrder.

```
Entity: PageOrderItem
  pageOrderId: String
  pageId: PageId
  sortOrder: Integer
  isHidden: Boolean
  addedAt: Timestamp
```

**Invariants**:
- `sortOrder` is unique within a given `pageOrderId`
- Each `(pageOrderId, pageId)` pair is unique
- Item rows are canonical authority for reorder/hide/audit behavior

---

### 11. ReaderSession
**Purpose**: Canonical normalized reader position state.

```
Entity: ReaderSession
  id: ReaderSessionId (UUID v4)
  comicId: ComicId (foreign key, immutable)
  chapterId: ChapterId (foreign key, immutable)
  pageIndex: Integer (0-based canonical position)
  activeTabPosition: Integer (reserved, for future multi-tab, default 0)
  createdAt: Timestamp
  updatedAt: Timestamp
```

**Invariants**:
- `id` is immutable
- `comicId` is immutable
- Position (chapter + page) is normalized in database (not JSON)
- At most one active ReaderSession per Comic
- ReaderSession is created or updated only by reader-position use cases
- `updatedAt` reflects latest position change
- All position state is explicit (no JSON blobs)

---

### 12. SourcePlatform
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

### 13. SourcePackageManifest
**Purpose**: Validated package contract payload/result (not durable installed package authority).

```
Entity: SourcePackageManifest
  id: String (deterministic hash of manifest content)
  sourcePlatformId: SourcePlatformId (optional, post-mutation reference)
  packageKey: String
  providerKey: String
  version: String (semver)
  archiveSha256: String (lowercase SHA-256 hex)
  manifestContract: Object (validated repository/package manifest contract payload)
  createdAt: Timestamp
```

**Invariants**:
- Validated against canonical repository/package manifest contract
- `providerKey` is identity metadata only and must not be inferred from display/provider name text
- `archiveSha256` is lowercase normalized SHA-256
- This entity is not durable installed package authority by itself
- Must not require SourcePlatform ownership before package artifact/store lifecycle completes

---

### 14. SourcePackageArtifact
**Purpose**: Durable verified source package artifact metadata (PackageStore-aligned authority).

```
Entity: SourcePackageArtifact
  id: String (UUID v4 or deterministic artifact ID)
  sourcePlatformId: SourcePlatformId (optional, post-activation reference)
  packageKey: String
  providerKey: String
  version: String (semver)
  archiveSha256: String (lowercase SHA-256 hex)
  packageStoreRef: String (durable storage reference)
  state: Enum (committed | active | orphaned | cleanup_pending | removed)
  createdAt: Timestamp
  updatedAt: Timestamp
```

**Invariants**:
- Durable artifact state is authoritative for package-store lifecycle
- Must not arbitrate source identity compatibility on its own
- State transitions follow source package lifecycle contract
- SourcePlatform reference is optional until successful source-platform mutation

---

### 15. Favorite
**Purpose**: User's marked work.

```
Entity: Favorite
  id: FavoriteId (UUID v4)
  comicId: ComicId (foreign key, immutable)
  markedAt: Timestamp
  lastAccessedAt: Timestamp (optional, future read-activity/favorite policy)
```

**Invariants**:
- One Favorite per Comic
- `comicId` is immutable
- `markedAt` is immutable
- `lastAccessedAt` is not updated by current reader-position core use case

---

### 16. ImportBatch
**Purpose**: Metadata for file imports (CBZ, PDF, directories).

```
Entity: ImportBatch
  id: ImportBatchId (UUID v4)
  sourceType: Enum (cbz | pdf | directory)
  sourceRef: String (adapter/import provenance reference, not canonical core identity)
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
  ├─→ ComicTitle (1:N)
  ├─→ Favorite (1:1, optional)
  └─→ ReaderSession (1:1)

Chapter (1) ──→ (N) Page
  ├─→ PageOrder (1:N)
  └─→ ChapterSourceLink (1:N)

Page (N) ──→ (1) StorageObject (optional durable bytes reference)
Page (1) ──→ (N) PageSourceLink
PageOrder (1) ──→ (N) PageOrderItem

Comic (1) ──→ (N) ComicSourceLink
ComicSourceLink (1) ──→ (N) ChapterSourceLink
ComicSourceLink (1) ──→ (N) PageSourceLink
SourcePlatform (1) ──→ (N) ComicSourceLink

SourcePackageManifest = validation payload (not owned by SourcePlatform)
SourcePackageArtifact (N) ──→ (0..1) SourcePlatform (optional, after activation)

ImportBatch ──→ Comic (optional, after completion)
```

---

## Validation Rules

### Comic
- `normalizedTitle` is normalized for matching/search only
- `normalizedTitle` is non-unique and must not be treated as canonical identity
- `id` must be valid UUID v4
- Both timestamps must be ISO8601

### Chapter
- `chapterNumber` is optional ordering hint only
- Canonical ordering policy may use `chapterNumber`, source order, `createdAt`, and `id`
- `comicId` must reference existing Comic
- `id` must be valid UUID v4
- Source provenance must be expressed via `ChapterSourceLink`, not direct source identity fields on `Chapter`

### Page
- `pageIndex` must be unique and contiguous within chapter
- `pageIndex` >= 0
- `chapterId` must reference existing Chapter
- `id` must be valid UUID v4
- Source provenance must be expressed via `PageSourceLink`, not direct source identity fields on `Page`

### ReaderSession
- `comicId` must reference existing Comic
- `chapterId` must reference existing Chapter
- `pageIndex` must be < page count in chapter
- At most one active ReaderSession per Comic
- ReaderSession is created/updated only by reader-position use cases

### SourcePlatform
- `canonicalKey` must be unique
- `kind` must be one of: local, remote, virtual
- `status` must be one of: active, disabled, deprecated
- `id` must be valid UUID v4

### SourcePackageManifest
- Must validate against canonical repository/package manifest contract
- `archiveSha256` must be normalized lowercase SHA-256
- `providerKey` is metadata and must not become source identity authority
- Must not be treated as durable installed package authority

### SourcePackageArtifact
- `archiveSha256` must be normalized lowercase SHA-256
- `state` must be one of: committed, active, orphaned, cleanup_pending, removed
- Must not decide source identity compatibility with existing source platform on its own

### Favorite
- `comicId` must reference existing Comic
- One Favorite per Comic
- `id` must be valid UUID v4

### ImportBatch
- Files must be ordered by index
- All checksums must be SHA256 format
- One ImportBatch completes to one Comic
- `sourceRef` is provenance only and must not be treated as canonical core identity

### Tags Projection Note
- `ComicMetadata.tags` is read-model projection only
- Canonical tag storage authority should be normalized tables (canonical tags, labels, source tags, tag mappings, user tags, and relation tables)
