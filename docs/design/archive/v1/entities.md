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
  libraryStatus: Enum (active | removed)
  removedAt: Timestamp (optional)
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
- `originHint` is derived from active content-bearing `SourceLink` rows and must be updated in the same transaction that changes source-link membership or status
- `originHint = unknown` when there are no active local/remote content-bearing links; `local` when active content sources are local-only; `remote` when active content sources are remote-only; `mixed` when both local and remote active content sources exist
- `SourcePlatform.kind = virtual` does not contribute to `originHint`
- `libraryStatus = removed` hides the comic from default library/browse results without deleting Chapters, Pages, PageOrders, ReaderSessions, or collection membership
- `removedAt` is present only when `libraryStatus = removed`
- `updatedAt` >= `createdAt`

**Relationships**:
- Owns: Chapter (1:N)
- Owns: ComicMetadata (1:1, optional)
- Owns: ComicTitle (1:N)
- Owns: SourceLink (1:N)
- Owns: ReaderSession (1:N, optional lifecycle rows)
- Referenced by: UserCollectionItem (N:1)

---

### 2. ComicMetadata
**Purpose**: Mutable display properties of a comic (separate from identity).

```
Entity: ComicMetadata
  comicId: ComicId (foreign key, immutable)
  title: DisplayTitle (user-facing, denormalized cache of primary ComicTitle)
  description: String (optional, long text)
  coverStatus: Enum (none | pending | local_only | synced)
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
- `title` must equal the `title` of the comic's primary `ComicTitle` (denormalized cache invariant)
- Primary-title mutations must update `ComicTitle` and `ComicMetadata.title` atomically in the same application transaction; a future server-backed multi-writer backend must add DB-backed enforcement or remove this duplicated cache
- `coverStatus` is the cover lifecycle authority; `coverPageId` and `coverStorageObjectId` are references whose allowed presence follows that status
- `coverStatus = none` requires both cover references to be absent
- `coverStatus = pending` means cover resolution/materialization is in progress and does not by itself prove a local page or storage object exists
- `coverStatus = local_only` requires at least one local cover reference (`coverPageId` or `coverStorageObjectId`)
- `coverStatus = synced` requires `coverStorageObjectId` and a synced authoritative storage placement
- If `coverPageId` and `coverStorageObjectId` are both present, the referenced Page must have the same `storageObjectId`; mismatched cover references are invalid and must be rejected
- Effective cover resolution uses `coverStorageObjectId` directly when present, otherwise derives a storage object from `coverPageId.storageObjectId` when that page has one
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
- At most one `titleKind = primary` row must exist per comic
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
  chapterNumber: DecimalString | null (optional ordering hint, e.g. "1", "1.5", "2")
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
- `parentChapterId` must not equal `id`
- The chapter hierarchy must be acyclic; mutations that would introduce a parent/child cycle must fail closed
- Maximum canonical nesting depth is 8 nodes including the current chapter; deeper structures require a new hierarchy contract before implementation
- Deleting a parent chapter must choose explicit subtree delete, explicit child reparent, or reject-if-children behavior; silent promotion of children to root-level chapters is invalid
- `chapterNumber` must be parsed and compared with decimal/numeric semantics, never binary floating-point arithmetic or lexicographic string ordering
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
- `kind = local` means content is sourced from local/imported storage; `kind = remote` means content is sourced from a network/provider integration
- `kind = virtual` is reserved for internal synthesized sources such as compatibility bridges or aggregate/projection providers; virtual platforms must not fetch remote content, own storage credentials, or stand in for user-defined collections
- User-defined cross-platform grouping is modeled by `UserCollection`, not by `SourcePlatform.kind = virtual`
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
- `(sourcePlatformId, remoteWorkId)` must be unique in the current schema and enforced by a DB unique index
- Current lifecycle is update-in-place across `active`, `candidate`, `rejected`, and `stale`; rejected/stale rows do not free the same provider work ID for another row unless a future provenance-history design changes the uniqueness model

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
  sourceOrder: Integer (optional, source-provided ordering hint)
  linkStatus: Enum (active | inactive | stale)
  confidence: Enum (manual | auto_high | auto_low)
  createdAt: Timestamp
  updatedAt: Timestamp
```

**Invariants**:
- Canonical chapter identity remains owned by `Chapter`
- `sourceLinkId` must reference an existing SourceLink
- `remoteChapterId` is provenance evidence, not canonical identity
- `sourceOrder`, when present, is source-provided ordering evidence; it is not canonical chapter identity
- First-canonical-chapter fallback uses the minimum non-null `sourceOrder` across active ChapterSourceLinks whose parent SourceLink and SourcePlatform are active
- `confidence` records chapter-level matching quality independently from comic-level SourceLink confidence

---

### 9. PageOrder
**Purpose**: Named page-ordering profile for a chapter.

```
Entity: PageOrder
  id: PageOrderId (UUID v4)
  chapterId: ChapterId (foreign key, immutable)
  orderType: Enum (source | user_override | import_detected | custom)
  status: Enum (active | inactive | superseded | archived)
  createdAt: Timestamp
  updatedAt: Timestamp
```

**Invariants**:
- Multiple PageOrder profiles may exist per chapter
- `orderType` is the single discriminator for what kind of ordering profile this is; there is no separate `orderKey`
- At most one PageOrder with `status = active` must exist per chapter
- `status` is lifecycle state, not a boolean; `superseded` records an order replaced by a newer profile, and `archived` records a deliberately retained non-current profile
- Item-level ordering is expressed by `PageOrderItem`, not delimited text blobs
- Page counts are derived from `PageOrderItem` rows and chapter pages; `PageOrder` must not store a separate `pageCount` cache

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
  pageId: PageId
  sourceLinkId: SourceLinkId (optional, last read-source context)
  sessionState: Enum (active | suspended | completed | abandoned)
  createdAt: Timestamp
  updatedAt: Timestamp
```

**Invariants**:
- `id` is immutable
- `comicId` is immutable
- `pageId` is the persisted position authority
- `sourceLinkId` is optional read-context evidence for source preference/fallback and is not part of position authority
- `chapterId` and `pageIndex` are derived by joining the referenced Page and must not be duplicated on ReaderSession
- `sessionState` is lifecycle state, not a boolean
- Multiple ReaderSession lifecycle rows may exist for one Comic, but at most one ReaderSession with `sessionState = active` may exist per Comic
- Only `sessionState = active` rows are resume candidates; abandoned/completed/suspended rows are historical lifecycle evidence unless a future resume policy says otherwise
- `pageId` must reference an existing Page whose Chapter belongs to the same Comic
- `sourceLinkId`, when present, must reference a SourceLink for the same Comic; stale source links may remain as historical context but must not block fallback to active alternatives
- `updatedAt` reflects the latest position change
- ReaderSession is created or updated only by reader-position use cases

---

### 12. UserCollection
**Purpose**: User-defined grouping of comics across platforms/sources.

```
Entity: UserCollection
  id: UserCollectionId (UUID v4)
  displayName: String
  description: String (optional)
  coverStorageObjectId: StorageObjectId (optional)
  sortOrder: Enum (manual | title | updated_at | last_read)
  createdAt: Timestamp
  updatedAt: Timestamp
```

**Invariants**:
- `id` is immutable
- `displayName` must be non-empty after normalization
- `sortOrder = manual` uses `UserCollectionItem.sortIndex` as display authority
- Non-manual sort orders derive display order at query time and must not mutate `sortIndex`
- `coverStorageObjectId`, when present, must reference an existing StorageObject with readable placement before display code treats the cover as available

---

### 13. UserCollectionItem
**Purpose**: Membership and manual ordering for a Comic inside a UserCollection.

```
Entity: UserCollectionItem
  id: UserCollectionItemId (UUID v4)
  collectionId: UserCollectionId
  comicId: ComicId
  sortIndex: Integer
  pinnedAt: Timestamp (optional)
  addedAt: Timestamp
```

**Invariants**:
- `id` is immutable
- `(collectionId, comicId)` must be unique
- `sortIndex` is unique within `collectionId`
- `comicId` may reference a Comic with `libraryStatus = removed`; removed comics are hidden from default library browse but retained in collections until explicitly removed from the collection
- Manual reorder mutations must update all affected `sortIndex` values atomically

---

### 14. StorageBackend
**Purpose**: Configured storage destination (local filesystem, WebDAV, etc.).

```
Entity: StorageBackend
  id: StorageBackendId (UUID v4)
  backendKey: String (stable unique identifier)
  displayName: String (user-facing name)
  backendKind: Enum (local_app_data | webdav | future)
  configJson: String (serialized backend configuration)
  configSchemaVersion: Integer
  secretRef: String (optional, reference to external credential store)
  status: Enum (active | disabled | deprecated)
  createdAt: Timestamp
  updatedAt: Timestamp
```

**Invariants**:
- `id` is immutable
- `backendKey` is unique
- `configSchemaVersion` identifies the parser/validator contract for `configJson`; readers must reject unsupported versions fail-closed
- `configJson` must not embed plaintext secrets; credentials are referenced via `secretRef`
- `secretRef` must point to an OS/platform credential store entry (for example Keychain, Keystore, or a deployment secret manager), not to raw secret material

---

### 15. StorageObject
**Purpose**: Logical storage object metadata tracked by the storage subsystem.

```
Entity: StorageObject
  id: StorageObjectId (UUID v4)
  objectKind: Enum (page_image | cover | archive | backup | cache)
  contentHash: String (optional, content-derived evidence)
  sizeBytes: Integer (optional)
  mimeType: String (optional)
  createdAt: Timestamp
  updatedAt: Timestamp
```

**Invariants**:
- `id` is immutable
- `contentHash`, when present, is evidence for deduplication and integrity verification; it is not the current primary identity authority
- Object existence does not imply that bytes are available on any backend; availability is determined by `StoragePlacement`
- A StorageObject with no readable placement is an unavailable object, not a successful byte reference
- Page/image loading must surface `STORAGE_OBJECT_UNAVAILABLE` or an explicit placeholder/retry state when the referenced StorageObject has no placement with readable bytes
- Authoritative placements should backfill `sizeBytes` and `mimeType` once bytes are materialized and verified

---

### 16. StoragePlacement
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
- `(storageObjectId, storageBackendId, objectKey)` must be unique
- At most one `role = authority` placement is logically valid per `storageObjectId`
- `syncStatus` tracks the lifecycle of bytes on the backend
- `role` governs eviction and replication policy

---

### 17. SourcePackageManifest
**Purpose**: Validated package contract payload/result (not durable installed package authority).

```
Entity: SourcePackageManifest
  id: SourcePackageManifestId (deterministic SHA-256 hash of canonical manifest content)
  sourcePlatformId: SourcePlatformId (optional, post-mutation reference)
  packageKey: String
  providerKey: String
  version: String (semver)
  trustTier: Enum (official | community | custom)
  publisherKeyFingerprint: String (optional, normalized public-key fingerprint)
  archiveSha256: String (lowercase SHA-256 hex)
  manifestContract: Object (validated repository/package manifest contract payload)
  createdAt: Timestamp
```

**Invariants**:
- Validated against canonical repository/package manifest contract
- `providerKey` is identity metadata only and must not be inferred from display/provider name text
- `trustTier` is repository-declared publisher trust intent, not proof of install-time verification by itself
- `publisherKeyFingerprint` is required for `trustTier = community` and `trustTier = official`; custom/self-signed packages may omit it only when the installer classifies the artifact as unverified and requires advanced confirmation
- `archiveSha256` is lowercase normalized SHA-256
- This entity is not durable installed package authority by itself
- Must not require SourcePlatform ownership before package artifact/store lifecycle completes

---

### 18. SourcePackageArtifact
**Purpose**: Durable verified source package artifact metadata (PackageStore-aligned authority).

```
Entity: SourcePackageArtifact
  id: String (UUID v4 or deterministic artifact ID)
  sourcePlatformId: SourcePlatformId (optional, post-activation reference)
  packageKey: String
  providerKey: String
  version: String (semver)
  archiveSha256: String (lowercase SHA-256 hex)
  verificationTier: Enum (official | community | custom | unverified)
  publisherKeyFingerprint: String (optional, normalized public-key fingerprint)
  signatureDigest: String (optional, normalized signature evidence digest)
  packageStoreRef: String (durable storage reference)
  state: Enum (committed | active | orphaned | cleanup_pending | removed)
  createdAt: Timestamp
  updatedAt: Timestamp
```

**Invariants**:
- Durable artifact state is authoritative for package-store lifecycle
- Must not arbitrate source identity compatibility on its own
- `verificationTier` records the install-time verification outcome after signature/authenticity and integrity checks
- `verificationTier = official` requires a valid signature by a trusted official key
- `verificationTier = community` requires a valid publisher signature by an accepted community key
- `verificationTier = custom` requires a valid self/custom publisher signature plus explicit advanced-user approval
- `verificationTier = unverified` is never eligible for one-button install or automatic activation
- State transitions follow source package lifecycle contract
- SourcePlatform reference is optional until successful source-platform mutation

---

### 19. OperationIdempotencyRecord
**Purpose**: Mutation replay ledger for caller-supplied idempotency keys.

```
Entity: OperationIdempotencyRecord
  operationName: String
  idempotencyKey: String
  inputHash: String (lowercase SHA-256 hex of canonical operation input)
  status: Enum (in_progress | completed | failed)
  resultType: String (optional, result discriminator)
  resultResourceId: String (optional, primary resource identifier for replay)
  resultJson: JsonObject (optional, serialized replay payload)
  resultSchemaVersion: String (optional)
  createdAt: Timestamp
  updatedAt: Timestamp
```

**Invariants**:
- Primary identity is the composite key `(operationName, idempotencyKey)`, not a UUID v4
- `inputHash` is computed from canonical JSON for the operation input after applying operation-defined defaults and normalization; object keys are sorted, absent optional fields are normalized consistently, and volatile fields such as timestamps are excluded unless explicitly part of the operation input
- `inputHash` uses SHA-256 for integrity/deduplication evidence, not as a secret-bearing authentication primitive
- Reusing the same `(operationName, idempotencyKey)` with a different `inputHash` returns `IDEMPOTENCY_CONFLICT` and performs no mutation
- `status = completed` requires replayable result evidence (`resultType` and either `resultResourceId` or `resultJson`)
- `resultSchemaVersion` is required when `resultJson` is present
- `status = in_progress` with a non-expired operation lease is not replayable; callers fail closed rather than polling or silently retrying the key
- Stale `in_progress` records are determined by `updatedAt + operationLeaseTtl`; default lease TTL is 5 minutes unless the operation explicitly defines a shorter TTL
- Long-running operations must renew `updatedAt` before the lease expires
- Stale `in_progress` records may be atomically reclaimed only when the caller supplies the same `inputHash`
- `status = failed` is not replayable as success; the same input may retry after the operation retry TTL, default 5 minutes from `updatedAt`
- Status transitions are `in_progress -> completed`, `in_progress -> failed`, and same-state no-op updates for deterministic retry handling; completed records are terminal

---

### 20. ImportBatch
**Purpose**: Deferred/legacy import provenance reference used by legacy import use cases.

```
Entity: ImportBatch
  id: ImportBatchId (UUID v4)
  sourceType: Enum (cbz | pdf | directory | unknown)
  sourceRef: String (adapter-owned reference, not canonical filesystem authority)
  status: Enum (in_progress | completed | failed | cancelled)
  fileCount: Integer (optional)
  errorCode: String (optional)
  startedAt: Timestamp
  completedAt: Timestamp (optional)
```

**Invariants**:
- `ImportBatch` is a Deferred/Legacy entity reference only; it is not current core canonical persistence authority unless a future import adapter contract promotes it
- `sourceRef` must not make absolute filesystem paths canonical storage identity
- `completedAt` is present only for terminal statuses (`completed`, `failed`, `cancelled`)
- Import use cases that reference `ImportBatchId` must treat the import adapter as owner of the file list and extraction details

---

## ID System

### ID Types
Primary runtime entity IDs are **UUID v4** (Universally Unique Identifiers, version 4):

```
ComicId                = UUID v4
ComicTitleId           = UUID v4
ChapterId              = UUID v4
PageId                 = UUID v4
PageOrderId            = UUID v4
PageOrderItemId        = UUID v4
ReaderSessionId        = UUID v4
UserCollectionId       = UUID v4
UserCollectionItemId   = UUID v4
SourcePlatformId       = UUID v4
SourceLinkId           = UUID v4
ChapterSourceLinkId    = UUID v4
StorageBackendId       = UUID v4
StorageObjectId        = UUID v4
StoragePlacementId     = UUID v4
ImportBatchId          = UUID v4 (Deferred/Legacy import reference)
CorrelationId          = String (UUID v4 format, used for tracing)
```

Content/package and composite identifiers that are explicitly not UUID v4:

```
OperationIdempotencyId  = Composite(operationName, idempotencyKey)
SourcePackageManifestId = String (deterministic SHA-256 hash of canonical manifest content)
SourcePackageArtifactId = String (UUID v4 or package-store deterministic artifact ID, as defined by package-store lifecycle authority)
```

### ID Ownership
- **ComicId**: Assigned by system at Comic creation
- **ComicTitleId**: Assigned by system at ComicTitle creation
- **ChapterId**: Assigned by system at Chapter creation
- **PageId**: Assigned by system at Page creation
- **PageOrderId**: Assigned by system at PageOrder creation
- **PageOrderItemId**: Assigned by system at PageOrderItem creation
- **ReaderSessionId**: Assigned by system at ReaderSession creation
- **UserCollectionId**: Assigned by system at UserCollection creation
- **UserCollectionItemId**: Assigned by system at UserCollectionItem creation
- **SourcePlatformId**: Assigned by system at SourcePlatform creation
- **SourceLinkId**: Assigned by system at SourceLink creation
- **ChapterSourceLinkId**: Assigned by system at ChapterSourceLink creation
- **StorageBackendId**: Assigned by system at StorageBackend creation
- **StorageObjectId**: Assigned by system at StorageObject creation
- **StoragePlacementId**: Assigned by system at StoragePlacement creation
- **ImportBatchId**: Assigned by import adapter/deferred import workflow
- **OperationIdempotencyId**: Derived from `(operationName, idempotencyKey)` composite identity
- **SourcePackageManifestId**: Derived from canonical manifest content hash; not randomly assigned
- **SourcePackageArtifactId**: Assigned by package-store lifecycle authority, not by generic entity creation

### ID Serialization
- Primary runtime entity IDs serialize as UUID strings (RFC 4122 format)
- Content/package identifiers serialize as normalized strings defined by their package-store contract
- IDs are projections for external consumption
- Database stores IDs as native UUID types (if supported) or strings

---

## Relationships Diagram

```
Comic (1) ──→ (N) Chapter
  ├─→ ComicMetadata (1:1, optional)
  ├─→ ComicTitle (1:N)
  ├─→ SourceLink (1:N)
  └─→ ReaderSession (1:N, optional lifecycle rows)

UserCollection (1) ──→ (N) UserCollectionItem
UserCollectionItem (N) ──→ (1) Comic

Chapter (1) ──→ (N) Page
  ├─→ PageOrder (1:N)
  └─→ ChapterSourceLink (1:N)

Page (N) ──→ (0..1) StorageObject (optional durable bytes reference)
Page (N) ──→ (0..1) ChapterSourceLink (optional source provenance back-reference)

PageOrder (1) ──→ (N) PageOrderItem
PageOrderItem (N) ──→ (1) Page

SourcePlatform (1) ──→ (N) SourceLink
SourceLink (1) ──→ (N) ChapterSourceLink
SourceLink (1) ──→ (N) ReaderSession (optional read-context evidence)
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
- `originHint` must be recomputed when active local/remote SourceLink membership changes
- `libraryStatus` must be one of: active, removed
- `removedAt` must be absent when `libraryStatus = active` and present when `libraryStatus = removed`
- `id` must be valid UUID v4
- Both timestamps must be ISO 8601

### ComicMetadata
- `comicId` must reference an existing Comic
- `title` must equal the `title` of the comic's active primary `ComicTitle` (denormalized cache invariant)
- Primary-title mutations must update `ComicTitle` and `ComicMetadata.title` in the same transaction
- `coverStatus` must be one of: none, pending, local_only, synced
- `coverStatus = none` requires both cover references to be absent
- `coverStatus = local_only` requires `coverPageId` or `coverStorageObjectId`
- `coverStatus = synced` requires `coverStorageObjectId`
- `coverPageId`, when present, must reference an existing Page
- `coverStorageObjectId`, when present, must reference an existing StorageObject
- If both cover references are present, `coverPageId.storageObjectId` must equal `coverStorageObjectId`

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
- `chapterNumber` must be a normalized decimal string and compared with decimal/numeric semantics
- `chapterKind` must be one of: season, volume, chapter, episode, oneshot, group
- Container-style `chapterKind` values (`season`, `volume`, `group`) may have children and normally should not own readable Pages directly unless a future mixed-node contract allows it
- Page-bearing imported/readable units should use `chapter`, `episode`, or `oneshot`
- `parentChapterId`, when present, must reference an existing Chapter in the same comic
- `parentChapterId` must not equal the Chapter's own `id`
- Chapter hierarchy mutations must reject cycles and reject nesting deeper than 8 nodes
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
- `orderType` must be one of: source, user_override, import_detected, custom
- `status` must be one of: active, inactive, superseded, archived
- At most one PageOrder with `status = active` per chapter

### PageOrderItem
- `pageOrderId` must reference an existing PageOrder
- `pageId` must reference an existing Page in the same chapter as the PageOrder
- `sortIndex` is unique within a `pageOrderId`
- Each `(pageOrderId, pageId)` pair is unique
- `id` must be valid UUID v4

### ReaderSession
- `comicId` must reference an existing Comic
- `pageId` must reference an existing Page
- `sourceLinkId`, when present, must reference an existing SourceLink for the same Comic
- The referenced Page's Chapter must belong to the ReaderSession's Comic
- `sessionState` must be one of: active, suspended, completed, abandoned
- At most one ReaderSession with `sessionState = active` per Comic
- ReaderSession is created/updated only by reader-position use cases

### UserCollection
- `displayName` must be non-empty after normalization
- `sortOrder` must be one of: manual, title, updated_at, last_read
- `coverStorageObjectId`, when present, must reference an existing StorageObject
- `id` must be valid UUID v4

### UserCollectionItem
- `collectionId` must reference an existing UserCollection
- `comicId` must reference an existing Comic
- `(collectionId, comicId)` must be unique
- `sortIndex` must be unique within a collection
- `id` must be valid UUID v4

### SourcePlatform
- `canonicalKey` must be unique and immutable
- `kind` must be one of: local, remote, virtual
- `kind = virtual` is internal synthetic/projection authority only and must not be used for user-defined collections
- `status` must be one of: active, disabled, deprecated
- Status transitions: active ↔ disabled; active → deprecated; disabled → deprecated; deprecated → deprecated (no-op). Transitions deprecated → active and deprecated → disabled are rejected.
- `id` must be valid UUID v4

### SourceLink
- `comicId` must reference an existing Comic
- `sourcePlatformId` must reference an existing SourcePlatform
- `(sourcePlatformId, remoteWorkId)` must be unique
- `linkStatus` must be one of: active, candidate, rejected, stale
- `confidence` must be one of: manual, auto_high, auto_low

### ChapterSourceLink
- `chapterId` must reference an existing Chapter
- `sourceLinkId` must reference an existing SourceLink
- `sourceOrder`, when present, must be an integer ordering hint and may be duplicated across distinct source links
- `linkStatus` must be one of: active, inactive, stale
- `confidence` must be one of: manual, auto_high, auto_low

### OperationIdempotencyRecord
- `(operationName, idempotencyKey)` is the composite identity
- `inputHash` must be lowercase SHA-256 hex of the canonical operation input
- `status` must be one of: in_progress, completed, failed
- `completed` records must carry replayable result evidence
- Same key with a different input hash must fail closed as `IDEMPOTENCY_CONFLICT`

### ImportBatch
- `id` must be valid UUID v4
- `status` must be one of: in_progress, completed, failed, cancelled
- `sourceType` must be one of: cbz, pdf, directory, unknown
- `sourceRef` is adapter-owned import evidence, not canonical storage authority
- This entity is Deferred/Legacy unless a future import adapter contract promotes it

### StorageBackend
- `backendKey` must be unique
- `backendKind` must be one of: local_app_data, webdav, future
- `status` must be one of: active, disabled, deprecated
- `configSchemaVersion` must be a positive integer supported by the backend parser
- `configJson` must not embed plaintext secrets
- `secretRef`, when present, must be an external credential-store reference and not raw credential material

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
- `id` must be the deterministic SHA-256 hash of the canonical manifest payload
- `archiveSha256` must be normalized lowercase SHA-256
- `trustTier` must be one of: official, community, custom
- `publisherKeyFingerprint` is required for official/community trust tiers
- `providerKey` is metadata and must not become source identity authority
- Must not be treated as durable installed package authority

### SourcePackageArtifact
- `archiveSha256` must be normalized lowercase SHA-256
- `verificationTier` must be one of: official, community, custom, unverified
- `state` must be one of: committed, active, orphaned, cleanup_pending, removed
- Must not decide source identity compatibility with existing source platform on its own
