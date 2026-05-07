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
  originHint: Enum (unknown | local | remote | mixed)
  createdAt: Timestamp
  updatedAt: Timestamp
```

**Invariants**:
- `id` is immutable
- `normalizedTitle` is normalized once at creation
- `normalizedTitle` is a non-unique matching/search signal only
- `normalizedTitle` must never decide canonical comic identity by itself
- Multiple comics may share the same `normalizedTitle`
- `originHint` indicates provenance category; defaults to `unknown` when indeterminate
- `updatedAt` >= `createdAt`

**Relationships**:
- Owns: Chapter (1:N)
- Owns: ComicMetadata (1:1, optional)
- Owns: ComicTitle (1:N)
- Owns: SourceLink (1:N)
- Owns: ReaderSession (1:1, optional)

---

### 2. ComicMetadata
**Purpose**: Mutable display properties of a comic (separate from identity).

```
Entity: ComicMetadata
  comicId: ComicId (foreign key, immutable)
  title: DisplayTitle (user-facing, denormalized cache of primary ComicTitle)
  description: String (optional, long text)
  coverPageId: PageId (optional, reference to cover page)
  coverStorageObjectId: StorageObjectId (optional, storage object reference)
  authorName: String (optional)
  metadata: JsonObject (optional, freeform structured metadata)
  createdAt: Timestamp
  updatedAt: Timestamp
```

**Invariants**:
- `comicId` is immutable
- Cannot exist without parent Comic
- `title` must equal the `title` of the comic's primary `ComicTitle` (denormalized cache invariant; must be kept in sync when the primary title changes)
- All other fields are mutable

---

### 3. ComicTitle
**Purpose**: Canonical title record separating primary title from source-provenance and alias evidence.

```
Entity: ComicTitle
  id: ComicTitleId (UUID v4)
  comicId: ComicId
  title: DisplayTitle
  normalizedTitle: String (non-unique matching signal)
  titleKind: Enum (primary | source | alias)
  locale: String (optional, BCP-47 language tag)
  sourcePlatformId: SourcePlatformId (optional, provenance reference)
  sourceLinkId: SourceLinkId (optional, provenance reference)
  createdAt: Timestamp
```

**Invariants**:
- Title records are evidence/projection surfaces, not canonical comic identity by themselves
- `normalizedTitle` remains non-unique
- At most one `titleKind = primary` should be active per comic
- `sourceLinkId`, when present, must reference an existing SourceLink for this comic

---

### 4. Chapter
**Purpose**: Structural unit of a comic containing an ordered set of pages.

```
Entity: Chapter
  id: ChapterId (UUID v4)
  comicId: ComicId (foreign key, immutable)
  parentChapterId: ChapterId (optional, for nested structures such as seasons/volumes)
  chapterKind: Enum (season | volume | chapter | episode | oneshot | group)
  chapterNumber: Float | null (optional ordering hint, e.g. 1.0, 1.5, 2.0)
  title: String (optional, chapter name)
  displayLabel: String (optional, override label for UI)
  createdAt: Timestamp
  updatedAt: Timestamp
```

**Invariants**:
- `id` is immutable
- `comicId` is immutable
- `chapterNumber` is nullable; when present it is an ordering hint only, not chapter identity authority
- `chapterNumber` is non-unique within a comic (two chapters may share the same number)
- `chapterNumber` must never serve as identity — identity is `id` only
- `parentChapterId`, when present, must reference an existing Chapter within the same comic
- Canonical ordering may combine `chapterNumber` with fallback policy (e.g. `createdAt`/`id`)
- Cannot exist without parent Comic

**Relationships**:
- Parent: Comic (N:1)
- Parent (optional): Chapter (N:1, via `parentChapterId`)
- Owns: Page (1:N)
- Owns: PageOrder (1:N)
- May have: ChapterSourceLink (1:N provenance edges)

---

### 5. Page
**Purpose**: A single image within a chapter.

```
Entity: Page
  id: PageId (UUID v4)
  chapterId: ChapterId (foreign key, immutable)
  pageIndex: Integer (0-based insertion/source index within chapter)
  storageObjectId: StorageObjectId (optional, storage object reference)
  chapterSourceLinkId: ChapterSourceLinkId (optional, source provenance back-reference)
  mimeType: String (optional, e.g. "image/jpeg")
  width: Integer (optional, pixels)
  height: Integer (optional, pixels)
  checksum: String (optional, content hash)
  createdAt: Timestamp
  updatedAt: Timestamp
```

**Invariants**:
- `id` is immutable
- `chapterId` is immutable
- `pageIndex` is unique within a chapter (no two pages share the same index)
- `pageIndex` is 0-based
- `pageIndex` is NOT required to be contiguous (gaps are permitted)
- Effective display order is governed by the active `PageOrder`/`PageOrderItem` policy, not `pageIndex` alone
- Cannot exist without parent Chapter

**Relationships**:
- Parent: Chapter (N:1)
- May reference: StorageObject (N:1, optional)
- May reference: ChapterSourceLink (N:1, optional)

---

### 6. SourcePlatform
**Purpose**: Provider/platform of comics (local filesystem, remote scraper, virtual).

```
Entity: SourcePlatform
  id: SourcePlatformId (UUID v4)
  canonicalKey: String (stable identifier, e.g. "copymanga", "local")
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
- Status transition rules:
  - `active` ↔ `disabled` (reversible)
  - `active` → `deprecated` (one-way)
  - `disabled` → `deprecated` (one-way)
  - `deprecated` → `deprecated` (no-op)
  - `deprecated` → `active` and `deprecated` → `disabled` are rejected

---

### 7. SourceLink
**Purpose**: Comic-level source provenance edge linking a canonical comic to a remote/platform work identifier.

```
Entity: SourceLink
  id: SourceLinkId (UUID v4)
  comicId: ComicId
  sourcePlatformId: SourcePlatformId
  remoteWorkId: String (stable identifier of the work on the source platform)
  remoteUrl: String (optional, sanitized source URL)
  displayTitle: String (optional, title as seen on the source platform)
  linkStatus: Enum (active | candidate | rejected | stale)
  confidence: Enum (manual | auto_high | auto_low)
  createdAt: Timestamp
  updatedAt: Timestamp
```

**Invariants**:
- Canonical comic identity remains owned by `Comic`, not this provenance edge
- `remoteWorkId` is provenance evidence, not canonical identity
- `(sourcePlatformId, remoteWorkId)` should be unique among active/candidate links

---

### 8. ChapterSourceLink
**Purpose**: Chapter-level source provenance edge linking a canonical chapter to a remote chapter identifier.

```
Entity: ChapterSourceLink
  id: ChapterSourceLinkId (UUID v4)
  chapterId: ChapterId
  sourceLinkId: SourceLinkId
  remoteChapterId: String (stable identifier of the chapter on the source platform)
  remoteUrl: String (optional, sanitized source URL)
  remoteLabel: String (optional, label as seen on the source platform)
  linkStatus: Enum (active | inactive | stale)
  createdAt: Timestamp
  updatedAt: Timestamp
```

**Invariants**:
- Canonical chapter identity remains owned by `Chapter`
- `sourceLinkId` must reference an existing SourceLink
- `remoteChapterId` is provenance evidence, not canonical identity

---

### 9. PageOrder
**Purpose**: Named page-ordering profile for a chapter.

```
Entity: PageOrder
  id: PageOrderId (UUID v4)
  chapterId: ChapterId (foreign key, immutable)
  orderKey: Enum (source | user | import_detected | custom)
  orderType: Enum (source | user_override | import_detected | custom)
  isActive: Boolean
  pageCount: Integer (cached count of pages in this order)
  createdAt: Timestamp
  updatedAt: Timestamp
```

**Invariants**:
- Multiple PageOrder profiles may exist per chapter
- At most one PageOrder with `isActive = true` should exist per chapter
- Item-level ordering is expressed by `PageOrderItem`, not delimited text blobs
- `pageCount` is a derived/cached count and must remain consistent with the number of `PageOrderItem` rows

---

### 10. PageOrderItem
**Purpose**: Item-level position record within a PageOrder.

```
Entity: PageOrderItem
  id: PageOrderItemId (UUID v4)
  pageOrderId: PageOrderId
  pageId: PageId
  sortIndex: Integer
  createdAt: Timestamp
```

**Invariants**:
- `sortIndex` is unique within a given `pageOrderId`
- Each `(pageOrderId, pageId)` pair is unique
- Item rows are canonical authority for display-order behavior

---

### 11. ReaderSession
**Purpose**: Persisted reader position state for a comic.

```
Entity: ReaderSession
  id: ReaderSessionId (UUID v4)
  comicId: ComicId (foreign key, immutable)
  chapterId: ChapterId
  pageId: PageId (optional)
  pageIndex: Integer (0-based canonical position)
  createdAt: Timestamp
  updatedAt: Timestamp
```

**Invariants**:
- `id` is immutable
- `comicId` is immutable
- At most one active ReaderSession per Comic
- Position (`chapterId` + `pageIndex`) is stored as normalized columns, not JSON blobs
- `pageId`, when present, must reference a page that belongs to `chapterId` and whose `pageIndex` equals the session's `pageIndex`; a session with a `pageId` that violates this constraint is invalid
- `pageId` is optional; its absence does not invalidate the session
- `updatedAt` reflects the latest position change
- ReaderSession is created or updated only by reader-position use cases

---

### 12. StorageBackend
**Purpose**: Configured storage destination (local filesystem, WebDAV, etc.).

```
Entity: StorageBackend
  id: StorageBackendId (UUID v4)
  backendKey: String (stable unique identifier)
  displayName: String (user-facing name)
  backendKind: Enum (local_app_data | webdav | future)
  configJson: String (serialized backend configuration)
  secretRef: String (optional, reference to external credential store)
  status: Enum (active | disabled | deprecated)
  createdAt: Timestamp
  updatedAt: Timestamp
```

**Invariants**:
- `id` is immutable
- `backendKey` is unique
- `configJson` must not embed plaintext secrets; credentials are referenced via `secretRef`

---

### 13. StorageObject
**Purpose**: Logical content object tracked by the storage subsystem.

```
Entity: StorageObject
  id: StorageObjectId (UUID v4)
  objectKind: Enum (page_image | cover | archive | backup | cache)
  contentHash: String (optional, content-addressable hash)
  sizeBytes: Integer (optional)
  mimeType: String (optional)
  createdAt: Timestamp
  updatedAt: Timestamp
```

**Invariants**:
- `id` is immutable
- `contentHash`, when present, is used for deduplication and integrity verification
- Object existence does not imply that bytes are available on any backend; availability is determined by `StoragePlacement`

---

### 14. StoragePlacement
**Purpose**: Placement record tracking where a StorageObject is stored on a specific backend.

```
Entity: StoragePlacement
  id: StoragePlacementId (UUID v4)
  storageObjectId: StorageObjectId
  storageBackendId: StorageBackendId
  objectKey: String (backend-relative path or key)
  role: Enum (authority | cache | mirror | staging)
  syncStatus: Enum (pending | uploading | synced | failed | evicted)
  lastVerifiedAt: Timestamp (optional)
  createdAt: Timestamp
  updatedAt: Timestamp
```

**Invariants**:
- `(storageObjectId, storageBackendId, objectKey)` should be unique
- `syncStatus` tracks the lifecycle of bytes on the backend
- `role` governs eviction and replication policy

---

### 15. SourcePackageManifest
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

### 16. SourcePackageArtifact
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

## ID System

### ID Types
All IDs are **UUID v4** (Universally Unique Identifiers, version 4):

```
ComicId                = UUID v4
ComicTitleId           = UUID v4
ChapterId              = UUID v4
PageId                 = UUID v4
PageOrderId            = UUID v4
PageOrderItemId        = UUID v4
ReaderSessionId        = UUID v4
SourcePlatformId       = UUID v4
SourceLinkId           = UUID v4
ChapterSourceLinkId    = UUID v4
StorageBackendId       = UUID v4
StorageObjectId        = UUID v4
StoragePlacementId     = UUID v4
CorrelationId          = String (UUID v4 format, used for tracing)
```

### ID Ownership
- **ComicId**: Assigned by system at Comic creation
- **ComicTitleId**: Assigned by system at ComicTitle creation
- **ChapterId**: Assigned by system at Chapter creation
- **PageId**: Assigned by system at Page creation
- **PageOrderId**: Assigned by system at PageOrder creation
- **PageOrderItemId**: Assigned by system at PageOrderItem creation
- **ReaderSessionId**: Assigned by system at ReaderSession creation
- **SourcePlatformId**: Assigned by system at SourcePlatform creation
- **SourceLinkId**: Assigned by system at SourceLink creation
- **ChapterSourceLinkId**: Assigned by system at ChapterSourceLink creation
- **StorageBackendId**: Assigned by system at StorageBackend creation
- **StorageObjectId**: Assigned by system at StorageObject creation
- **StoragePlacementId**: Assigned by system at StoragePlacement creation

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
  ├─→ SourceLink (1:N)
  └─→ ReaderSession (1:1, optional)

Chapter (1) ──→ (N) Page
  ├─→ PageOrder (1:N)
  └─→ ChapterSourceLink (1:N)

Page (N) ──→ (0..1) StorageObject (optional durable bytes reference)
Page (N) ──→ (0..1) ChapterSourceLink (optional source provenance back-reference)

PageOrder (1) ──→ (N) PageOrderItem
PageOrderItem (N) ──→ (1) Page

SourcePlatform (1) ──→ (N) SourceLink
SourceLink (1) ──→ (N) ChapterSourceLink
SourceLink (N) ──→ (1) SourcePlatform

StorageObject (1) ──→ (N) StoragePlacement
StoragePlacement (N) ──→ (1) StorageBackend

SourcePackageManifest = validation payload (not owned by SourcePlatform)
SourcePackageArtifact (N) ──→ (0..1) SourcePlatform (optional, after activation)
```

---

## Validation Rules

### Comic
- `normalizedTitle` is normalized for matching/search only
- `normalizedTitle` is non-unique and must not be treated as canonical identity
- `originHint` must be one of: unknown, local, remote, mixed
- `id` must be valid UUID v4
- Both timestamps must be ISO 8601

### ComicMetadata
- `comicId` must reference an existing Comic
- `title` must equal the `title` of the comic's active primary `ComicTitle` (denormalized cache invariant)
- `coverPageId`, when present, must reference an existing Page
- `coverStorageObjectId`, when present, must reference an existing StorageObject

### ComicTitle
- `comicId` must reference an existing Comic
- `titleKind` must be one of: primary, source, alias
- `normalizedTitle` is non-unique
- At most one `titleKind = primary` per comic
- `sourceLinkId`, when present, must reference an existing SourceLink belonging to this comic

### Chapter
- `comicId` must reference an existing Comic
- `chapterNumber` is optional; when present it is an ordering hint only, not identity
- `chapterNumber` is non-unique within a comic
- `chapterKind` must be one of: season, volume, chapter, episode, oneshot, group
- `parentChapterId`, when present, must reference an existing Chapter in the same comic
- `id` must be valid UUID v4
- Source provenance must be expressed via `ChapterSourceLink`, not direct source identity fields on `Chapter`

### Page
- `pageIndex` must be unique within the chapter
- `pageIndex` >= 0
- `pageIndex` is NOT required to be contiguous; gaps are permitted
- `chapterId` must reference an existing Chapter
- `id` must be valid UUID v4
- `chapterSourceLinkId`, when present, must reference an existing ChapterSourceLink
- `storageObjectId`, when present, must reference an existing StorageObject

### PageOrder
- `chapterId` must reference an existing Chapter
- `orderKey` must be one of: source, user, import_detected, custom
- `orderType` must be one of: source, user_override, import_detected, custom
- At most one PageOrder with `isActive = true` per chapter
- `pageCount` must remain consistent with the number of associated `PageOrderItem` rows

### PageOrderItem
- `pageOrderId` must reference an existing PageOrder
- `pageId` must reference an existing Page in the same chapter as the PageOrder
- `sortIndex` is unique within a `pageOrderId`
- Each `(pageOrderId, pageId)` pair is unique
- `id` must be valid UUID v4

### ReaderSession
- `comicId` must reference an existing Comic
- `chapterId` must reference an existing Chapter belonging to that Comic
- `pageIndex` >= 0
- `pageId`, when present, must reference a Page that belongs to `chapterId` and whose `pageIndex` equals the session's `pageIndex`; any other value renders the session invalid
- At most one active ReaderSession per Comic
- ReaderSession is created/updated only by reader-position use cases

### SourcePlatform
- `canonicalKey` must be unique and immutable
- `kind` must be one of: local, remote, virtual
- `status` must be one of: active, disabled, deprecated
- Status transitions: active ↔ disabled; active → deprecated; disabled → deprecated; deprecated → deprecated (no-op). Transitions deprecated → active and deprecated → disabled are rejected.
- `id` must be valid UUID v4

### SourceLink
- `comicId` must reference an existing Comic
- `sourcePlatformId` must reference an existing SourcePlatform
- `linkStatus` must be one of: active, candidate, rejected, stale
- `confidence` must be one of: manual, auto_high, auto_low

### ChapterSourceLink
- `chapterId` must reference an existing Chapter
- `sourceLinkId` must reference an existing SourceLink
- `linkStatus` must be one of: active, inactive, stale

### StorageBackend
- `backendKey` must be unique
- `backendKind` must be one of: local_app_data, webdav, future
- `status` must be one of: active, disabled, deprecated
- `configJson` must not embed plaintext secrets

### StorageObject
- `objectKind` must be one of: page_image, cover, archive, backup, cache
- `id` must be valid UUID v4

### StoragePlacement
- `storageObjectId` must reference an existing StorageObject
- `storageBackendId` must reference an existing StorageBackend
- `role` must be one of: authority, cache, mirror, staging
- `syncStatus` must be one of: pending, uploading, synced, failed, evicted

### SourcePackageManifest
- Must validate against canonical repository/package manifest contract
- `archiveSha256` must be normalized lowercase SHA-256
- `providerKey` is metadata and must not become source identity authority
- Must not be treated as durable installed package authority

### SourcePackageArtifact
- `archiveSha256` must be normalized lowercase SHA-256
- `state` must be one of: committed, active, orphaned, cleanup_pending, removed
- Must not decide source identity compatibility with existing source platform on its own
