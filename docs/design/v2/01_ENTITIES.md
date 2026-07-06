# Entities Specification

**Language-agnostic entity definitions for Venera canonical runtime.**

> Scope: this file is the canonical authority for the core content domain
> (Content / ContentSection / ContentUnit / provenance / storage / sessions /
> collections / idempotency / recommendation graph signals). Feature-domain entities live in their feature docs:
> auth & audit entities in `06_SECURITY_AUTH_RECOMMENDATION.md`,
> plugin/package entities in `05_PLUGIN_SYSTEM.md` and `08_SOURCE_PACKAGE_LIFECYCLE.md`,
> download/notification/update/stats entities in `07_FEATURES.md`.
> Recommendation algorithms and vector queries live in `06_SECURITY_AUTH_RECOMMENDATION.md`;
> the durable content graph/signal rows live here because they reference core Content.
> Naming follows the v2 convention (`Content`, not `Comic`); see `SUMMARY.md`.

---

## Entity Catalog

### 1. Content
**Purpose**: Canonical identity for a content work.

```
Entity: Content
  id: ContentId (UUID v4)
  contentType: ContentType (immutable)
  normalizedTitle: String (lowercase, normalized matching/search signal)
  originHint: Enum (unknown | local | remote | mixed)
  libraryStatus: Enum (active | removed)
  removedAt: Timestamp (optional)
  createdAt: Timestamp
  updatedAt: Timestamp

ContentType enum:
  comic | webtoon | illustrated | novel | article | document | note
```

**Invariants**:
- `id` is immutable
- `contentType` is immutable after creation; it selects the ContentProfile (reader mode, unit type, feature flags — see `04_PACKAGES_AND_PIECES.md`), it does not change identity or schema
- `normalizedTitle` is normalized once at creation
- `normalizedTitle` is a non-unique matching/search signal only
- `normalizedTitle` must never decide canonical content identity by itself
- Multiple contents may share the same `normalizedTitle`
- `originHint` indicates provenance category; defaults to `unknown` when indeterminate
- `originHint` is derived from active content-bearing `SourceLink` rows and must be updated in the same transaction that changes source-link membership or status
- `originHint = unknown` when there are no active local/remote content-bearing links; `local` when active content sources are local-only; `remote` when active content sources are remote-only; `mixed` when both local and remote active content sources exist
- `SourcePlatform.kind = virtual` does not contribute to `originHint`
- `libraryStatus = removed` hides the content from default library/browse results without deleting ContentSections, ContentUnits, ContentUnitOrders, ReadingSessions, or collection membership
- `removedAt` is present only when `libraryStatus = removed`
- `updatedAt` >= `createdAt`

**Relationships**:
- Owns: ContentSection (1:N)
- Owns: ContentMetadata (1:1, optional)
- Owns: ContentTitle (1:N)
- Owns: SourceLink (1:N)
- Owns: ReadingSession (1:N, optional lifecycle rows)
- Referenced by: UserCollectionItem (N:1)

---

### 2. ContentMetadata
**Purpose**: Mutable display properties of a content (separate from identity).

```
Entity: ContentMetadata
  contentId: ContentId (foreign key, immutable)
  title: DisplayTitle (user-facing, denormalized cache of primary ContentTitle)
  description: String (optional, long text)
  coverStatus: Enum (none | pending | local_only | synced)
  coverUnitId: ContentUnitId (optional, reference to cover unit)
  coverStorageObjectId: StorageObjectId (optional, storage object reference)
  authorName: String (optional)
  contentRating: Enum (safe | moderate | adult_only | explicit) (optional; feature-domain Target — content filtering in 07_FEATURES.md)
  userRating: Integer (optional, 1..5; user/library rating used by search and backup)
  metadata: JsonObject (optional, freeform structured metadata)
  createdAt: Timestamp
  updatedAt: Timestamp
```

**Invariants**:
- `contentId` is immutable
- Cannot exist without parent Content
- `title` must equal the `title` of the content's primary `ContentTitle` (denormalized cache invariant)
- Primary-title mutations must update `ContentTitle` and `ContentMetadata.title` atomically in the same application transaction; a future server-backed multi-writer backend must add DB-backed enforcement or remove this duplicated cache
- `coverStatus` is the cover lifecycle authority; `coverUnitId` and `coverStorageObjectId` are references whose allowed presence follows that status
- `coverStatus = none` requires both cover references to be absent
- `coverStatus = pending` means cover resolution/materialization is in progress and does not by itself prove a local unit or storage object exists
- `coverStatus = local_only` requires at least one local cover reference (`coverUnitId` or `coverStorageObjectId`)
- `coverStatus = synced` requires `coverStorageObjectId` and a synced authoritative storage placement
- `contentRating`, when present, must be one of `safe`, `moderate`, `adult_only`, `explicit`; enabled content filters treat absent ratings as most restricted
- `userRating`, when present, must be an integer from 1 through 5 and is user preference evidence, not content-safety classification
- If `coverUnitId` and `coverStorageObjectId` are both present, the referenced ContentUnit must have the same `storageObjectId`; mismatched cover references are invalid and must be rejected
- Effective cover resolution uses `coverStorageObjectId` directly when present, otherwise derives a storage object from `coverUnitId.storageObjectId` when that unit has one
- Deleting a ContentUnit referenced by `coverUnitId` is valid only if cover lifecycle remains internally consistent in the same transaction: either `coverStorageObjectId` remains a valid cover reference, or the deletion flow clears cover references and sets `coverStatus = none`. Deleting the last local-only cover reference while leaving `coverStatus = local_only` is invalid.
- All other fields are mutable

---

### 3. ContentTitle
**Purpose**: Canonical title record separating primary title from source-provenance and alias evidence.

```
Entity: ContentTitle
  id: ContentTitleId (UUID v4)
  contentId: ContentId
  title: DisplayTitle
  normalizedTitle: String (non-unique matching signal)
  titleKind: Enum (primary | source | alias)
  locale: String (optional, BCP-47 language tag)
  sourcePlatformId: SourcePlatformId (optional, provenance reference)
  sourceLinkId: SourceLinkId (optional, provenance reference)
  createdAt: Timestamp
```

**Invariants**:
- Title records are evidence/projection surfaces, not canonical content identity by themselves
- `normalizedTitle` remains non-unique
- At most one `titleKind = primary` row must exist per content
- Logical uniqueness on `(contentId, normalizedTitle, locale, sourcePlatformId)` treats missing `locale` and missing `sourcePlatformId` as value-bearing buckets; backends must enforce this with an expression/functional unique index or an explicitly named application-layer guard
- `sourceLinkId`, when present, must reference an existing SourceLink for this content

---

### 4. ContentSection
**Purpose**: Structural unit of a content containing an ordered set of units.

```
Entity: ContentSection
  id: ContentSectionId (UUID v4)
  contentId: ContentId (foreign key, immutable)
  parentSectionId: ContentSectionId (optional, for nested structures such as seasons/volumes)
  sectionKind: Enum
    season | volume | chapter | episode | oneshot | group   <- visual content
    section | entry | article | part                        <- text content
  sectionNumber: DecimalString | null (optional ordering hint, e.g. "1", "1.5", "2")
  title: String (optional, section name)
  displayLabel: String (optional, override label for UI)
  createdAt: Timestamp
  updatedAt: Timestamp
```

**Invariants**:
- `id` is immutable
- `contentId` is immutable
- `sectionNumber` is nullable; when present it is an ordering hint only, not section identity authority
- `sectionNumber` is non-unique within a content (two sections may share the same number)
- `sectionNumber` must never serve as identity — identity is `id` only
- `parentSectionId`, when present, must reference an existing ContentSection within the same content
- `parentSectionId` must not equal `id`
- The section hierarchy must be acyclic; mutations that would introduce a parent/child cycle must fail closed
- Maximum canonical nesting depth is 8 nodes including the current section; deeper structures require a new hierarchy contract before implementation
- Deleting a parent section must choose explicit subtree delete, explicit child reparent, or reject-if-children behavior; silent promotion of children to root-level sections is invalid
- `sectionNumber` must be parsed and compared with decimal/numeric semantics, never binary floating-point arithmetic or lexicographic string ordering
- Canonical ordering may combine `sectionNumber` with fallback policy (e.g. `createdAt`/`id`)
- Cannot exist without parent Content

**Relationships**:
- Parent: Content (N:1)
- Parent (optional): ContentSection (N:1, via `parentSectionId`)
- Owns: ContentUnit (1:N)
- Owns: ContentUnitOrder (1:N)
- May have: SectionSourceLink (1:N provenance edges)

---

### 5. ContentUnit
**Purpose**: Atomic reading unit within a section (image page, text block, PDF page).

```
Entity: ContentUnit
  id: ContentUnitId (UUID v4)
  sectionId: ContentSectionId (foreign key, immutable)
  unitIndex: Integer (0-based insertion/source index within section)
  unitType: Enum (image | text | pdf_page | markdown | html)

  # image / pdf_page units
  storageObjectId: StorageObjectId (optional, storage object reference)
  mimeType: String (optional, e.g. "image/jpeg")
  width: Integer (optional, pixels)
  height: Integer (optional, pixels)
  checksum: String (optional, content hash)

  # text / markdown / html units
  textContent: String (optional)
  textHash: String (optional, content hash of textContent)

  sectionSourceLinkId: SectionSourceLinkId (optional, source provenance back-reference)
  createdAt: Timestamp
  updatedAt: Timestamp
```

**Invariants**:
- `id` is immutable
- `sectionId` is immutable
- `unitIndex` is unique within a section (no two units share the same index)
- `unitIndex` is 0-based
- `unitIndex` is NOT required to be contiguous (gaps are permitted)
- `unitType` selects which field group is meaningful: `image`/`pdf_page` units carry storage references, `text`/`markdown`/`html` units carry `textContent`; a unit must not populate both groups
- `textHash`, when present, must be the content hash of `textContent` (recomputed on text mutation)
- Effective display order is governed by the active `ContentUnitOrder`/`ContentUnitOrderItem` policy, not `unitIndex` alone
- Cannot exist without parent ContentSection

**Relationships**:
- Parent: ContentSection (N:1)
- May reference: StorageObject (N:1, optional)
- May reference: SectionSourceLink (N:1, optional)

---

### 6. SourcePlatform
**Purpose**: Provider/platform of contents (local filesystem, remote scraper, virtual).

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
**Purpose**: Content-level source provenance edge linking a canonical content to a remote/platform work identifier.

```
Entity: SourceLink
  id: SourceLinkId (UUID v4)
  contentId: ContentId
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
- Canonical content identity remains owned by `Content`, not this provenance edge
- `remoteWorkId` is provenance evidence, not canonical identity
- `(sourcePlatformId, remoteWorkId)` must be unique in the current schema and enforced by a DB unique index
- Current lifecycle is update-in-place across `active`, `candidate`, `rejected`, and `stale`; rejected/stale rows do not free the same provider work ID for another row unless a future provenance-history design changes the uniqueness model

---

### 8. SectionSourceLink
**Purpose**: ContentSection-level source provenance edge linking a canonical section to a remote section identifier.

```
Entity: SectionSourceLink
  id: SectionSourceLinkId (UUID v4)
  sectionId: ContentSectionId
  sourceLinkId: SourceLinkId
  remoteContentSectionId: String (stable identifier of the section on the source platform)
  remoteUrl: String (optional, sanitized source URL)
  remoteLabel: String (optional, label as seen on the source platform)
  sourceOrder: Integer (optional, source-provided ordering hint)
  linkStatus: Enum (active | inactive | stale)
  confidence: Enum (manual | auto_high | auto_low)
  createdAt: Timestamp
  updatedAt: Timestamp
```

**Invariants**:
- Canonical section identity remains owned by `ContentSection`
- `sourceLinkId` must reference an existing SourceLink
- `remoteContentSectionId` is provenance evidence, not canonical identity
- `sourceOrder`, when present, is source-provided ordering evidence; it is not canonical section identity
- First-canonical-section fallback uses the minimum non-null `sourceOrder` across active SectionSourceLinks whose parent SourceLink and SourcePlatform are active
- `confidence` records section-level matching quality independently from content-level SourceLink confidence

---

### 9. ContentUnitOrder
**Purpose**: Named unit-ordering profile for a section.

```
Entity: ContentUnitOrder
  id: ContentUnitOrderId (UUID v4)
  sectionId: ContentSectionId (foreign key, immutable)
  orderType: Enum (source | user_override | import_detected | custom)
  status: Enum (active | inactive | superseded | archived)
  createdAt: Timestamp
  updatedAt: Timestamp
```

**Invariants**:
- Multiple ContentUnitOrder profiles may exist per section
- `orderType` is the single discriminator for what kind of ordering profile this is; there is no separate `orderKey`
- At most one ContentUnitOrder with `status = active` must exist per section
- `status` is lifecycle state, not a boolean; `superseded` records an order replaced by a newer profile, and `archived` records a deliberately retained non-current profile
- Item-level ordering is expressed by `ContentUnitOrderItem`, not delimited text blobs
- ContentUnit counts are derived from `ContentUnitOrderItem` rows and section units; `ContentUnitOrder` must not store a separate `unitCount` cache

---

### 10. ContentUnitOrderItem
**Purpose**: Item-level position record within a ContentUnitOrder.

```
Entity: ContentUnitOrderItem
  id: ContentUnitOrderItemId (UUID v4)
  orderId: ContentUnitOrderId
  unitId: ContentUnitId
  sortIndex: Integer
  createdAt: Timestamp
```

**Invariants**:
- `sortIndex` is unique within a given `orderId`
- Each `(orderId, unitId)` pair is unique
- Item rows are canonical authority for display-order behavior

---

### 11. ReadingSession
**Purpose**: Persisted reader position state for a content.

```
Entity: ReadingSession
  id: ReadingSessionId (UUID v4)
  contentId: ContentId (foreign key, immutable)
  unitId: ContentUnitId
  sourceLinkId: SourceLinkId (optional, last read-source context)
  sessionState: Enum (active | suspended | completed | abandoned)
  createdAt: Timestamp
  updatedAt: Timestamp
```

**Invariants**:
- `id` is immutable
- `contentId` is immutable
- `unitId` is the persisted position authority
- `sourceLinkId` is optional read-context evidence for source preference/fallback and is not part of position authority
- `sectionId` and `unitIndex` are derived by joining the referenced ContentUnit and must not be duplicated on ReadingSession
- `sessionState` is lifecycle state, not a boolean
- Multiple ReadingSession lifecycle rows may exist for one Content, but at most one ReadingSession with `sessionState = active` may exist per Content
- Only `sessionState = active` rows are resume candidates; abandoned/completed/suspended rows are historical lifecycle evidence unless a future resume policy says otherwise
- `unitId` must reference an existing ContentUnit whose ContentSection belongs to the same Content
- `sourceLinkId`, when present, must reference a SourceLink for the same Content; stale source links may remain as historical context but must not block fallback to active alternatives
- `updatedAt` reflects the latest position change
- ReadingSession is created or updated only by reader-position use cases

---

### 12. UserCollection
**Purpose**: User-defined grouping of contents across platforms/sources.

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
**Purpose**: Membership and manual ordering for a Content inside a UserCollection.

```
Entity: UserCollectionItem
  id: UserCollectionItemId (UUID v4)
  collectionId: UserCollectionId
  contentId: ContentId
  sortIndex: Integer
  pinnedAt: Timestamp (optional)
  addedAt: Timestamp
```

**Invariants**:
- `id` is immutable
- `(collectionId, contentId)` must be unique
- `sortIndex` is unique within `collectionId`
- `contentId` may reference a Content with `libraryStatus = removed`; removed contents are hidden from default library browse but retained in collections until explicitly removed from the collection
- Manual reorder mutations must update all affected `sortIndex` values atomically

---

### 14. StorageBackend
**Purpose**: Configured storage destination (local filesystem, WebDAV, etc.).

```
Entity: StorageBackend
  id: StorageBackendId (UUID v4)
  backendKey: String (stable unique identifier)
  displayName: String (user-facing name)
  backendKind: Enum (local_app_data | webdav | plugin | future)
  pluginKey: String (optional; required when backendKind = plugin)
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
- `pluginKey` is present iff `backendKind = plugin`; it identifies the storage plugin that owns the backend instance
- `configSchemaVersion` identifies the parser/validator contract for `configJson`; readers must reject unsupported versions fail-closed
- `configJson` must not embed plaintext secrets; credentials are referenced via `secretRef`
- `secretRef` must point to an OS/platform credential store entry (for example Keychain, Keystore, or a deployment secret manager), not to raw secret material

---

### 15. StorageObject
**Purpose**: Logical storage object metadata tracked by the storage subsystem.

```
Entity: StorageObject
  id: StorageObjectId (UUID v4)
  objectKind: Enum (unit_image | cover | archive | backup | cache)
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
- ContentUnit/image loading must surface `STORAGE_OBJECT_UNAVAILABLE` or an explicit placeholder/retry state when the referenced StorageObject has no placement with readable bytes
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
- v2 direction: the plugin-based import pipeline (`ImportJob` in `05_PLUGIN_SYSTEM.md`) supersedes ImportBatch for new work; ImportBatch is retained only so legacy import use cases remain readable
- `sourceRef` must not make absolute filesystem paths canonical storage identity
- `completedAt` is present only for terminal statuses (`completed`, `failed`, `cancelled`)
- Import use cases that reference `ImportBatchId` must treat the import adapter as owner of the file list and extraction details

---

### 21. ContentRelationship
**Purpose**: Durable relationship edge between two canonical Content records.

```
Entity: ContentRelationship
  id: ContentRelationshipId (UUID v4)
  sourceContentId: ContentId
  targetContentId: ContentId
  relationshipType: Enum (translation | edition | sequel | prequel | spin_off | adaptation | alternative | colored)
  sourceLanguage: String (optional, BCP-47 language tag)
  targetLanguage: String (optional, BCP-47 language tag)
  sourceContentType: ContentType
  targetContentType: ContentType
  confidence: Enum (manual | auto_high | auto_low)
  evidenceSignals: JsonArray
  createdAt: Timestamp
  updatedAt: Timestamp
```

**Invariants**:
- `id` is immutable
- `sourceContentId` and `targetContentId` must reference existing Content rows
- `sourceContentId` must not equal `targetContentId`
- The stored edge is directed evidence: `(A, B, translation)` and `(B, A, translation)` are distinct rows
- Product surfaces that need symmetric "related content" behavior must query both source and target directions explicitly; the write path must not silently insert an implicit reverse edge
- `(sourceContentId, targetContentId, relationshipType)` must be unique
- `sourceContentType` and `targetContentType` are denormalized evidence copied from the referenced Content rows at relationship creation/update time
- `evidenceSignals` must contain sanitized, non-secret signal metadata only

---

### 22. ContentRelationshipProposal
**Purpose**: Candidate relationship produced by recommendation/matching signals before user or policy review.

```
Entity: ContentRelationshipProposal
  id: ContentRelationshipProposalId (UUID v4)
  sourceContentId: ContentId
  targetContentId: ContentId
  suggestedType: String
  confidence: Enum (manual | auto_high | auto_low)
  signalSummary: JsonObject
  status: Enum (pending | accepted | rejected | expired)
  reviewedAt: Timestamp (optional)
  expiresAt: Timestamp
  createdAt: Timestamp
```

**Invariants**:
- `id` is immutable
- `sourceContentId` and `targetContentId` must reference existing Content rows
- `sourceContentId` must not equal `targetContentId`
- `status = pending` proposals are reviewable until `expiresAt`
- Terminal statuses are `accepted`, `rejected`, and `expired`
- `reviewedAt` is present only for `accepted` or `rejected`
- Accepting a proposal must create or update the corresponding ContentRelationship in the same transaction that marks the proposal `accepted`
- `signalSummary` must be sanitized and must not contain raw user text, secrets, or provider credentials

---

### 23. ContentFingerprint
**Purpose**: Lightweight matching signals for duplicate detection and recommendation prefiltering.

```
Entity: ContentFingerprint
  id: ContentFingerprintId (UUID v4)
  contentId: ContentId
  coverPHash: String (optional)
  coverDHash: String (optional)
  sectionCount: Integer
  unitCountHint: Integer
  externalIds: JsonObject
  signalVersion: String
  createdAt: Timestamp
  updatedAt: Timestamp
```

**Invariants**:
- `contentId` is unique; at most one active fingerprint row exists per Content
- Fingerprints are matching evidence only and must never become canonical Content identity
- `sectionCount` and `unitCountHint` are non-negative derived hints
- `externalIds` may contain provider IDs only as provenance/matching evidence; source identity remains SourceLink-owned
- Recomputing fingerprints must update `signalVersion` and `updatedAt`

---

### 24. ContentVector
**Purpose**: Embedding/vector signals for search and recommendation ranking.

```
Entity: ContentVector
  contentId: ContentId
  titleVec: Float32Array (optional)
  tagVec: Float32Array (optional)
  contentRank: Float
  lastComputedAt: Timestamp
  signalVersion: String
```

**Invariants**:
- `contentId` is the primary identity and must reference existing Content
- Vectors are derived signals only and must be rebuilt from canonical content/title/tag evidence when signal contracts change
- Vector dimensions and embedding model identity are governed by `signalVersion`; readers must reject unsupported versions fail-closed
- `contentRank` is derived ranking evidence, not mutable user preference authority
- Missing vectors mean the content is unavailable for vector search, not missing from the library

---

## ID System

### ID Types
Primary runtime entity IDs are **UUID v4** (Universally Unique Identifiers, version 4):

```
ContentId                = UUID v4
ContentTitleId           = UUID v4
ContentSectionId              = UUID v4
ContentUnitId                 = UUID v4
ContentUnitOrderId            = UUID v4
ContentUnitOrderItemId        = UUID v4
ReadingSessionId        = UUID v4
UserCollectionId       = UUID v4
UserCollectionItemId   = UUID v4
ContentRelationshipId         = UUID v4
ContentRelationshipProposalId = UUID v4
ContentFingerprintId          = UUID v4
SourcePlatformId       = UUID v4
SourceLinkId           = UUID v4
SectionSourceLinkId    = UUID v4
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
- **ContentId**: Assigned by system at Content creation
- **ContentTitleId**: Assigned by system at ContentTitle creation
- **ContentSectionId**: Assigned by system at ContentSection creation
- **ContentUnitId**: Assigned by system at ContentUnit creation
- **ContentUnitOrderId**: Assigned by system at ContentUnitOrder creation
- **ContentUnitOrderItemId**: Assigned by system at ContentUnitOrderItem creation
- **ReadingSessionId**: Assigned by system at ReadingSession creation
- **UserCollectionId**: Assigned by system at UserCollection creation
- **UserCollectionItemId**: Assigned by system at UserCollectionItem creation
- **ContentRelationshipId**: Assigned by system at ContentRelationship creation
- **ContentRelationshipProposalId**: Assigned by system at proposal creation
- **ContentFingerprintId**: Assigned by system when fingerprint row is created
- **SourcePlatformId**: Assigned by system at SourcePlatform creation
- **SourceLinkId**: Assigned by system at SourceLink creation
- **SectionSourceLinkId**: Assigned by system at SectionSourceLink creation
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
Content (1) ──→ (N) ContentSection
  ├─→ ContentMetadata (1:1, optional)
  ├─→ ContentTitle (1:N)
  ├─→ SourceLink (1:N)
  ├─→ ReadingSession (1:N, optional lifecycle rows)
  ├─→ ContentFingerprint (0..1)
  └─→ ContentVector (0..1)

ContentRelationship (N) ──→ (1) Content as sourceContent
ContentRelationship (N) ──→ (1) Content as targetContent
ContentRelationshipProposal (N) ──→ (1) Content as sourceContent
ContentRelationshipProposal (N) ──→ (1) Content as targetContent

UserCollection (1) ──→ (N) UserCollectionItem
UserCollectionItem (N) ──→ (1) Content

ContentSection (1) ──→ (N) ContentUnit
  ├─→ ContentUnitOrder (1:N)
  └─→ SectionSourceLink (1:N)

ContentUnit (N) ──→ (0..1) StorageObject (optional durable bytes reference)
ContentUnit (N) ──→ (0..1) SectionSourceLink (optional source provenance back-reference)

ContentUnitOrder (1) ──→ (N) ContentUnitOrderItem
ContentUnitOrderItem (N) ──→ (1) ContentUnit

SourcePlatform (1) ──→ (N) SourceLink
SourceLink (1) ──→ (N) SectionSourceLink
SourceLink (1) ──→ (N) ReadingSession (optional read-context evidence)
SourceLink (N) ──→ (1) SourcePlatform

StorageObject (1) ──→ (N) StoragePlacement
StoragePlacement (N) ──→ (1) StorageBackend

SourcePackageManifest = validation payload (not owned by SourcePlatform)
SourcePackageArtifact (N) ──→ (0..1) SourcePlatform (optional, after activation)
```

---

## Validation Rules

### Content
- `contentType` must be one of: comic, webtoon, illustrated, novel, article, document, note
- `contentType` is immutable after creation
- `normalizedTitle` is normalized for matching/search only
- `normalizedTitle` is non-unique and must not be treated as canonical identity
- `originHint` must be one of: unknown, local, remote, mixed
- `originHint` must be recomputed when active local/remote SourceLink membership changes
- `libraryStatus` must be one of: active, removed
- `removedAt` must be absent when `libraryStatus = active` and present when `libraryStatus = removed`
- `id` must be valid UUID v4
- Both timestamps must be ISO 8601

### ContentMetadata
- `contentId` must reference an existing Content
- `title` must equal the `title` of the content's active primary `ContentTitle` (denormalized cache invariant)
- Primary-title mutations must update `ContentTitle` and `ContentMetadata.title` in the same transaction
- `coverStatus` must be one of: none, pending, local_only, synced
- `coverStatus = none` requires both cover references to be absent
- `coverStatus = local_only` requires `coverUnitId` or `coverStorageObjectId`
- `coverStatus = synced` requires `coverStorageObjectId`
- `coverUnitId`, when present, must reference an existing ContentUnit
- `coverStorageObjectId`, when present, must reference an existing StorageObject
- If both cover references are present, `coverUnitId.storageObjectId` must equal `coverStorageObjectId`
- Unit deletion must not leave `coverStatus = local_only` with no remaining local cover reference
- `contentRating`, when present, must be one of: safe, moderate, adult_only, explicit (ordered scale); an ENABLED content filter treats absent rating as most restricted — fail closed (see 07_FEATURES.md)

### ContentTitle
- `contentId` must reference an existing Content
- `titleKind` must be one of: primary, source, alias
- `normalizedTitle` is non-unique
- At most one `titleKind = primary` per content
- Logical title uniqueness must treat NULL `locale` and NULL `sourcePlatformId` as concrete buckets, not as duplicate escape hatches
- `sourceLinkId`, when present, must reference an existing SourceLink belonging to this content

### ContentSection
- `contentId` must reference an existing Content
- `sectionNumber` is optional; when present it is an ordering hint only, not identity
- `sectionNumber` is non-unique within a content
- `sectionNumber` must be a normalized decimal string and compared with decimal/numeric semantics
- `sectionKind` must be one of: season, volume, chapter, episode, oneshot, group, section, entry, article, part
- Container-style `sectionKind` values (`season`, `volume`, `group`) may have children and normally should not own readable ContentUnits directly unless a future mixed-node contract allows it
- Unit-bearing imported/readable nodes should use `chapter`, `episode`, or `oneshot` for visual content, and `section`, `entry`, `article`, or `part` for text content
- `parentSectionId`, when present, must reference an existing ContentSection in the same content
- `parentSectionId` must not equal the ContentSection's own `id`
- ContentSection hierarchy mutations must reject cycles and reject nesting deeper than 8 nodes
- `id` must be valid UUID v4
- Source provenance must be expressed via `SectionSourceLink`, not direct source identity fields on `ContentSection`

### ContentUnit
- `unitIndex` must be unique within the section
- `unitIndex` >= 0
- `unitIndex` is NOT required to be contiguous; gaps are permitted
- `unitType` must be one of: image, text, pdf_page, markdown, html
- `unitType in (image, pdf_page)` units must not populate `textContent`/`textHash`; `unitType in (text, markdown, html)` units must not populate storage/image fields
- `sectionId` must reference an existing ContentSection
- `id` must be valid UUID v4
- `sectionSourceLinkId`, when present, must reference an existing SectionSourceLink
- `storageObjectId`, when present, must reference an existing StorageObject

### ContentUnitOrder
- `sectionId` must reference an existing ContentSection
- `orderType` must be one of: source, user_override, import_detected, custom
- `status` must be one of: active, inactive, superseded, archived
- At most one ContentUnitOrder with `status = active` per section

### ContentUnitOrderItem
- `orderId` must reference an existing ContentUnitOrder
- `unitId` must reference an existing ContentUnit in the same section as the ContentUnitOrder
- `sortIndex` is unique within a `orderId`
- Each `(orderId, unitId)` pair is unique
- `id` must be valid UUID v4

### ReadingSession
- `contentId` must reference an existing Content
- `unitId` must reference an existing ContentUnit
- `sourceLinkId`, when present, must reference an existing SourceLink for the same Content
- The referenced ContentUnit's ContentSection must belong to the ReadingSession's Content
- `sessionState` must be one of: active, suspended, completed, abandoned
- At most one ReadingSession with `sessionState = active` per Content
- ReadingSession is created/updated only by reader-position use cases

### UserCollection
- `displayName` must be non-empty after normalization
- `sortOrder` must be one of: manual, title, updated_at, last_read
- `coverStorageObjectId`, when present, must reference an existing StorageObject
- `id` must be valid UUID v4

### UserCollectionItem
- `collectionId` must reference an existing UserCollection
- `contentId` must reference an existing Content
- `(collectionId, contentId)` must be unique
- `sortIndex` must be unique within a collection
- `id` must be valid UUID v4

### ContentRelationship
- `sourceContentId` and `targetContentId` must reference existing Content rows
- `sourceContentId` must not equal `targetContentId`
- `relationshipType` must be one of: translation, edition, sequel, prequel, spin_off, adaptation, alternative, colored
- `(sourceContentId, targetContentId, relationshipType)` must be unique
- Relationship rows are directed evidence; callers that need symmetric related-content behavior must query both directions explicitly
- `confidence` must be one of: manual, auto_high, auto_low
- `evidenceSignals` must be sanitized JSON evidence, not raw source payloads or secrets

### ContentRelationshipProposal
- `sourceContentId` and `targetContentId` must reference existing Content rows
- `sourceContentId` must not equal `targetContentId`
- `status` must be one of: pending, accepted, rejected, expired
- `expiresAt` must be present
- Accepting a proposal must create/update the target ContentRelationship atomically with the proposal status change
- Terminal proposals must not be reopened in place

### ContentFingerprint
- `contentId` must reference an existing Content and be unique
- `sectionCount` and `unitCountHint` must be non-negative
- `signalVersion` must be present and understood by readers
- Fingerprints are matching evidence only, not canonical identity

### ContentVector
- `contentId` must reference an existing Content
- At least one vector field should be present for vector-search eligibility
- `signalVersion` must identify the embedding/vector contract
- Unsupported vector `signalVersion` values must be ignored or rejected fail-closed, not coerced

### SourcePlatform
- `canonicalKey` must be unique and immutable
- `kind` must be one of: local, remote, virtual
- `kind = virtual` is internal synthetic/projection authority only and must not be used for user-defined collections
- `status` must be one of: active, disabled, deprecated
- Status transitions: active ↔ disabled; active → deprecated; disabled → deprecated; deprecated → deprecated (no-op). Transitions deprecated → active and deprecated → disabled are rejected.
- `id` must be valid UUID v4

### SourceLink
- `contentId` must reference an existing Content
- `sourcePlatformId` must reference an existing SourcePlatform
- `(sourcePlatformId, remoteWorkId)` must be unique
- `linkStatus` must be one of: active, candidate, rejected, stale
- `confidence` must be one of: manual, auto_high, auto_low

### SectionSourceLink
- `sectionId` must reference an existing ContentSection
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
- `backendKind` must be one of: local_app_data, webdav, plugin, future
- `pluginKey` must be present when `backendKind = plugin` and absent for non-plugin backends
- `status` must be one of: active, disabled, deprecated
- `configSchemaVersion` must be a positive integer supported by the backend parser
- `configJson` must not embed plaintext secrets
- `secretRef`, when present, must be an external credential-store reference and not raw credential material

### StorageObject
- `objectKind` must be one of: unit_image, cover, archive, backup, cache
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
