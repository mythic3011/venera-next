# Use Cases Specification

**Language-agnostic application layer use cases (business workflows).**

> Scope: core content domain use cases (create/update/remove, source links, reader,
> collections). Feature-domain use cases (download manager, notifications, content
> update/refresh, reading stats, search, backup) live in `07_FEATURES.md`.
> Naming follows v2 (`Content`/`ContentSection`/`ContentUnit`); see `SUMMARY.md`.

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

> **v2 is the sole design.** This is a clean v2 build — there is no legacy runtime to reconcile and the old codebase is out of scope. v2 uses the generalized `Content` / `ContentSection` / `ContentUnit` naming throughout. The labels below describe **design-contract maturity**, not the state of any existing code.

Status model in this document:
- `Implemented (Core+DB)` = stable, settled contract — schema + use case are finalized and ready to build against
- `Target` = corrected pre-stable design contract; still being firmed up before it is treated as settled
- `Planned Canonical` = intended canonical direction, not yet a settled contract
- `Deferred/Legacy` = out of scope for now; kept for reference only

Auth/permission note:
- Current runtime/core canonical slice does not define a user/auth domain model.
- Any `userId` attribution and permission enforcement belongs to adapter/auth layer policy until an explicit core auth contract is added.

---

## Content Management Use Cases

### Implemented (Core+DB)

### UC-001: Create New Content

**Purpose**: Add a new content to the library.

**Actors**: User, System

**Pre-conditions**:
- Title is not empty

**Input**:
```
{
  title: String (non-empty)
  contentType: ContentType (optional, default "comic")
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
8. System creates Content, ContentMetadata, and primary ContentTitle record in a single transaction
9. `content_metadata.title` is set to the same value as `content_titles.title` for the primary title row (denormalized cache; must be equal at creation time)
10. Return Content, ContentMetadata, and primary ContentTitle

**Post-conditions**:
- Content record exists in database
- ContentMetadata populated from input; `content_metadata.title` equals primary `content_titles.title`
- Primary ContentTitle record exists with `titleKind = "primary"`
- `created_at` / `updated_at` timestamps recorded on Content and ContentMetadata
- If `idempotencyKey` provided: OperationIdempotency record exists with `status = "completed"` and serialized result
- No reading_sessions record is created at content creation time

**Error Handling**:
- If the same `idempotencyKey` already exists as non-expired `in_progress` or non-retryable `failed`: return a fail-closed non-replayable error, no changes
- If the same `idempotencyKey` is reused with a different canonical input hash: return `IDEMPOTENCY_CONFLICT`, no changes
- If database fails: return `StorageError`, transaction rolled back

**Output**:
```
{
  content: Content (with assigned ID)
  metadata: ContentMetadata
  primaryTitle: ContentTitle
}
```

Invariant note:
- `metadata.title === primaryTitle.title` at creation. `content_metadata.title` is a denormalized cache of the primary title and must equal it at the time of creation.

Diagnostics note:
- May record diagnostics event `content.created` through diagnostics port when configured.

---

### UC-002: Import Content from File

**Status**: Deferred/Legacy (not current core canonical authority)

**Purpose**: Import content from CBZ, PDF, or directory.

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
5. System creates ContentMetadata from importMetadata
6. System creates Content if title provided
7. System creates ContentSections with ContentUnits for each image
8. System marks ImportBatch as completed
9. System emits `content.imported` event
10. Return imported Content and ImportBatch

**Post-conditions**:
- Content created with ContentMetadata
- ContentUnits created in canonical order
- ImportBatch marked completed with `completed_at`
- Reader position initialized
- (Favorites deferred — no favorite side-effect in the active contract)

**Error Handling**:
- If source file not readable: throw `NotFoundError`
- If no valid images: throw `ValidationError`
- If import already exists: throw `DuplicateError`
- If creation fails: ImportBatch is marked `failed` or `cancelled` by the import adapter; canonical writes are rolled back

**Output**:
```
{
  content: Content (newly created or matched)
  importBatch: ImportBatch (with completed_at)
  unitsCreated: Integer (count)
  event: DiagnosticsEvent (eventName: "content.imported")
}
```

---

### UC-003: Update Content Metadata

**Purpose**: Modify content properties (title, description, cover).

**Actors**: User, System

**Pre-conditions**:
- Content exists

**Input**:
```
{
  contentId: ContentId
  title: String (optional)
  description: String (optional)
  coverStatus: "none" | "pending" | "local_only" | "synced" (optional)
  coverUnitId: ContentUnitId (optional)
  coverStorageObjectId: StorageObjectId (optional)
  authorName: String (optional)
  contentRating: ContentRating (optional)
  userRating: Integer (optional, 1..5)
  tags: List<TagReference> (optional, projection shape)
}
```

**Main Flow**:
1. System retrieves Content by ID
2. If new title is provided:
   - system normalizes the display title and normalized matching title
   - system updates the active primary ContentTitle row
   - system updates `ContentMetadata.title` from that primary ContentTitle value in the same transaction
   - if no primary ContentTitle row exists, system fails closed with `ValidationError` rather than writing the metadata cache directly
3. If cover references are provided, system validates the cover lifecycle rules:
   - `coverStatus = "none"` requires both cover references to be absent
   - `coverStatus = "local_only"` requires `coverUnitId` or `coverStorageObjectId`
   - `coverStatus = "synced"` requires `coverStorageObjectId` with readable authoritative placement
   - if both cover references are present, `coverUnitId.storageObjectId` must equal `coverStorageObjectId`
4. If `contentRating` is provided, system validates it against the ordered ContentRating scale from `07_FEATURES.md`
5. If `userRating` is provided, system validates integer range 1..5
6. System updates non-title ContentMetadata fields with provided values
7. System emits `content.updated` event with changes
8. Return updated Content, ContentMetadata, and primary ContentTitle when title changed

**Post-conditions**:
- ContentMetadata modified
- If `title` changed, the primary ContentTitle and `ContentMetadata.title` are equal
- `updated_at` timestamp refreshed
- Content marked as modified

**Error Handling**:
- If content not found: throw `NotFoundError`
- If title is invalid/empty after normalization rules: throw `ValidationError`
- If cover references conflict or required cover bytes are unavailable: throw `ValidationError`
- If rating values are outside their declared enums/ranges: throw `ValidationError`

**Output**:
```
{
  content: Content (updated)
  metadata: ContentMetadata (updated)
  primaryTitle: ContentTitle (when title changed)
  changes: Object (fields that changed)
  event: DiagnosticsEvent (eventName: "content.updated")
}
```

---

### UC-004: Remove Content from Library

**Status**: Planned Canonical

**Purpose**: Hide a content from default library surfaces without destroying reader progress or child data.

**Actors**: User, System

**Pre-conditions**:
- Content exists
- Adapter/auth layer may enforce delete permissions (outside current core authority)

**Input**:
```
{
  contentId: ContentId
  confirmRemoval: Boolean (must be true)
}
```

**Main Flow**:
1. System retrieves Content by ID
2. If `confirmRemoval` is false → ValidationError
3. System updates `Content.libraryStatus = "removed"` and sets `removedAt`
4. System emits `content.removed` event
5. Return success

**Post-conditions**:
- Content row remains in database with `libraryStatus = "removed"`
- ContentSections, ContentUnits, ContentUnitOrders, ReadingSession, SourceLinks, and collection membership remain intact
- Default library/search/browse surfaces exclude removed contents unless explicitly requested
- Storage/cache files are not deleted

**Error Handling**:
- If content not found: throw `NotFoundError`
- If confirmation not provided: throw `ValidationError`
- If permission denied: throw `ForbiddenError`
- If update fails: throw `StorageError`, transaction rolled back

**Output**:
```
{
  success: Boolean
  removedContentId: ContentId
  event: DiagnosticsEvent (eventName: "content.removed")
}
```

---

### UC-004b: Permanently Delete Content

**Status**: Planned Canonical

**Purpose**: Irreversibly purge a content and all dependent records.

**Actors**: User, System

**Pre-conditions**:
- Content exists
- User explicitly requests permanent deletion, not normal library removal
- Adapter/auth layer may enforce delete permissions (outside current core authority)

**Input**:
```
{
  contentId: ContentId
  confirmPermanentDeletion: Boolean (must be true)
}
```

**Main Flow**:
1. System retrieves Content by ID
2. If `confirmPermanentDeletion` is false -> ValidationError
3. System explicitly deletes or cascades ReadingSession lifecycle rows for the Content before ContentSection/ContentUnit cascades can invalidate `reading_sessions.unitId`
4. System deletes Content, cascading to ContentSections, ContentUnits, ContentUnitOrders, SourceLinks, and UserCollectionItem rows
5. System emits `content.deleted` event
6. Return success

**Post-conditions**:
- Content and dependent database rows are deleted
- Storage/cache byte cleanup is a separate storage lifecycle concern unless explicitly included by a future storage purge contract

**Error Handling**:
- If content not found: throw `NotFoundError`
- If confirmation not provided: throw `ValidationError`
- If permission denied: throw `ForbiddenError`
- If deletion fails: throw `StorageError`, transaction rolled back

**Output**:
```
{
  success: Boolean
  deletedContentId: ContentId
  event: DiagnosticsEvent (eventName: "content.deleted")
}
```

---

## One-Time Old Venera Data Import Use Cases (canonical v2)

> **Distinct from UC-002** (ordinary file/CBZ import) and plugin `ImportJob` (05). This trusted, user-initiated legacy-data importer has its own `LegacyImportDataset`, `LegacyImportBatch`, mappings, staging records and receipt. Source-file scope is exactly `local.db`, `history.db`, `local_favorite.db`, `appdata.json`, `implicitData.json`; legacy Unified Store `venera.db` is rejected. See 01/02 and 17 for domain, DDL and negative cases.

### UC-LGI-001: Inspect Legacy Distributed Data (dry run)

**Actors:** trusted local user, host-only legacy import application service. Third-party JS source plugins are **not authorized** callers.

**Input:** `{ selectedLegacyFileRefs: AllowedRoleRef[], authorizedMediaRoots?: TrustedPathGrant[], proposedDatasetId?: UUID }`. Roles and canonical resolved handles are resolved by a trusted picker; names and paths inside old DB rows confer **no** filesystem/network permission.

**Flow:**
1. Reject disallowed roles, duplicate/conflicting input handles, old Unified Store schema signatures (including files renamed `local.db`) and the new v2 database as input.
2. Acquire SQLite-consistent read-only snapshots for supplied DB roles, respecting journal sidecars via SQLite; separately copy bounded JSON role inputs. Incomplete journal/lock/corruption means a typed per-file failure, no source mutation.
3. Verify schema signature, integrity and per-file budgets. Parse only reviewed old-table/JSON variants in an isolated adapter; never execute legacy Dart/JS or input SQL.
4. Resolve an existing `LegacyImportDataset` identity using trusted user intent, or reserve a provisional, **not-yet-persisted** dataset UUID for the proposed plan. Derive stable `LegacyRecordKey` with dataset/file role/table/folder/type/id rather than digest or title. Persist a newly created dataset only after explicit approved apply. Generate record digests, candidate Content/Section/Unit identities and category readiness.
5. Validate available media against granted roots; detect symlink/path escapes, missing media and ambiguous section/page ordering.
6. Return a **read-only preview** with per-file counts, candidate merges, existing canonical progress conflicts, unresolved/pending image favorites, tag deferrals and destination artifact budget. No canonical writes or account/network effects.

**Output:** `LegacyImportPreview` with temporary snapshot handles, proposed import plan digest, file/category classifications, required user choices, phase readiness and typed errors. A dry run does **not** create ImportJob or a new ReadingSession.

**Errors:** `LEGACY_INPUT_NOT_ALLOWED`, `LEGACY_UNIFIED_STORE_UNSUPPORTED`, `LEGACY_SCHEMA_UNSUPPORTED`, `LEGACY_SNAPSHOT_UNAVAILABLE`, `LEGACY_SOURCE_CORRUPT`, `LEGACY_MEDIA_OUTSIDE_GRANT`, `LEGACY_DATA_BUDGET_EXCEEDED`.

**L0 record provenance gate (implementation slice):** before reserving a `LegacyRecordMapping`, the trusted service checks the approved Batch, owner, live lease, and exact record key + typed source row digest emitted from that lease's **same inspected snapshot**. As of 2026-10-10, this record-level adapter exists only for `local.db.comics`; other input roles can be previewed but **must not** mutate mappings or canonical library state until their own attestation adapters are reviewed. A batch snapshot SHA-256 or caller-supplied row digest alone is insufficient proof. Records may be updated only from newly reviewed/approved evidence. No third-party plugin can make or spoof this host-only call.

### UC-LGI-002: Approve and Apply One-Time Import

**Input:** trusted user-gesture approval of an exact preview/plan digest, dataset identity, explicit `skip | keep_both | merge_verified | metadata_only | defer` decisions, retention policy and granted media roots.

**Flow:**
1. Approve **the exact, already-previewed immutable source snapshot lease** (the trusted host's `leaseRef`, dataset/owner scope, five-role SHA-256 manifest and plan revision), not a second read from mutable original files. A modified source file after snapshot creation does not alter the approved lease; creating a new snapshot or changing the selected inputs requires a fresh preview and explicit approval. Reject expired/revoked leases, and re-check the live lease before every mapping mutation. The current L0 lease is memory-only: after a process restart, explicit re-preview/re-approval is required, not unsafe recovery by trusting old saved hashes.
2. For each approved work, consult `LegacyRecordMapping` *before* allocating canonical IDs. Same key/digest already committed → unchanged; same key/new digest → reviewed update; unmapped key → fresh IDs. A different dataset with the same legacy integer IDs remains independent.
3. Stage authorized media in private managed temporary storage, verify counts/content hashes, persist journal intents, promote bytes safely without changing original sources, then atomically commit **one complete** Content/Section/Unit/order/StoragePlacement subtree, mapping and journal state to the fresh v2 database. **SQLite does not cover filesystem writes.**
4. For `history.db`, perform UC-LGI-003 below; for `local_favorite.db` and tags defer until collection/taxonomy capabilities exist (L2/M2). Image favorites remain a separate deferred category until designed. Apply `appdata.json`/`implicitData.json` **only** through individual trusted allowlisted keys/type conversions.
5. Record unresolved source-only work references, unreadable media and ambiguous positions in `LegacyUnresolvedRecord`; never fabricate ContentUnits or SourceLinks to satisfy a foreign key.
6. Re-read committed storage and mapping evidence; create/repair `LegacyImportReceipt` from **committed** state and report `verified | partial | failed | cancelled`. A crash can leave complete per-content commits; retries must resume rather than duplicate.

**Postconditions:** legacy originals untouched; no automatic plugin install, network, login or secret import. Import may partially complete. “Fully imported” is **forbidden** if any user-requested category is deferred/unverified. Cancellation after committed subtrees records partial work and **does not** implicitly delete already imported content.

**Errors:** `LEGACY_APPROVAL_STALE`, `LEGACY_DATASET_CONFLICT`, `LEGACY_RECORD_CONFLICT`, `LEGACY_ASSET_MISSING`, `LEGACY_STORAGE_PROMOTION_FAILED`, `LEGACY_PARTIAL_IMPORT`. Explicitly report outcome by category/file.

### UC-LGI-003: Reconcile Legacy Reader Position

**Input:** legacy history evidence `(type,id,ep,page,readEpisode,chapter_group,time)`, verified dataset record mappings, candidate canonical Content/Section/Unit order, and an explicit conflict decision if the v2 ReadingSession already exists.

**Flow and invariant:**
1. Match work through a verified dataset-scoped ID mapping, **not title or cover alone**. Remote history requiring an unavailable source identity stays unresolved.
2. Validate the chapter/group encoding against an inspected legacy version, and candidate page order against verified real images. Both 0-based and 1-based interpretations are **ambiguity checks**, never a “choose whichever fits” fallback.
3. Return `VERIFIED_UNIT` only for one uniquely corroborated canonical unit belonging to the matched content; otherwise `REVIEW_REQUIRED`, `UNRESOLVED` or `UNSUPPORTED_FORMAT`. Preserve the original historical timestamp as staging evidence.
4. If a current v2 active ReadingSession exists, default **keep current** and ask the trusted UI before replacing it; a legacy timestamp is not grounds for silent rewind.
5. Only after verification and approval call `UC-005b Update Reader Position` (or a documented import-aware command that enforces the same canonical constraints). Never write raw `page` to `reading_sessions.unit_id` or forge `updated_at`.

**Postconditions:** uncertain history stays historical/unresolved; it is not an active reading position. An existing active v2 session is preserved unless the user explicitly chooses a verified imported position.

### UC-LGI-004: Resume, Review and Purge Import Evidence

- **Resume**: load an approved batch, verify the same dataset/plan and replay-safe mapping identities, inspect durable `LegacyAssetJournal` and canonical DB records, repair receipt/counters, resume verified pending commits. A new input snapshot is a **new preview**, not silent resumption with widened permission.
- **Review**: trusted UI displays local bounded unresolved categories and candidate matches; an explicit decision resolves/dismisses them. Tag mapping requires M2; remote source/account matching requires M3; image favorites require a distinct feature/model.
- **Purge**: remove expired private snapshot/staging or user-selected review evidence. Do not delete original legacy media or canonical content; never GC a promoted file referenced by an active StoragePlacement. Mapping deletion as part of “forget legacy input” requires a separate explicit confirmation and warning that future re-runs may lose dedupe evidence.
- **No autonomous retry** of login, website scraping, plugin execution, network fetch or missing-file search.

**Boundary between authoritative contracts:** `UC-002` and `05 ImportJob` remain the normal file import paths. Legacy LGI operations call the canonical Content/Storage/Reader/Collection use cases internally, not their plugin-facing import APIs, and never alter the general import plugin protocol.

---

## Source Link Management Use Cases

### Planned Canonical

These use cases own the cross-platform identity/provenance write path. `SourceLink` merges source provenance into an existing canonical Content; it does not create a user-defined collection and does not make provider IDs canonical content identity.

### UC-SRC-001: Add SourceLink to Content

**Purpose**: Attach a provider/platform work to an existing canonical Content.

**Actors**: User, System, SourceRuntime

**Pre-conditions**:
- Content exists
- SourcePlatform exists and is not `deprecated`
- `(sourcePlatformId, remoteWorkId)` is not already linked in the current schema

**Input**:
```
{
  contentId: ContentId
  sourcePlatformId: SourcePlatformId
  remoteWorkId: String
  remoteUrl: String (optional)
  displayTitle: String (optional)
  linkStatus: "active" | "candidate" (optional, default "candidate" for automated matches, "active" for explicit manual attach)
  confidence: "manual" | "auto_high" | "auto_low"
}
```

**Main Flow**:
1. System validates Content and SourcePlatform exist
2. System rejects `SourcePlatform.status = "deprecated"`
3. System validates `(sourcePlatformId, remoteWorkId)` uniqueness using the DB unique constraint
4. System creates SourceLink
5. System recomputes and updates `Content.originHint` in the same transaction
6. System emits `source_link.added` event
7. Return SourceLink and updated Content

**Post-conditions**:
- SourceLink exists for the Content
- `Content.originHint` reflects active local/remote content-bearing SourceLink membership

**Error Handling**:
- If content or platform not found: throw `NotFoundError`
- If provider work is already linked: throw `DuplicateError`
- If platform is deprecated or input is invalid: throw `ValidationError`

### UC-SRC-002: Update SourceLink Status

**Purpose**: Approve, reject, stale, or reactivate a content-level source provenance edge.

**Input**:
```
{
  sourceLinkId: SourceLinkId
  linkStatus: "active" | "candidate" | "rejected" | "stale"
  confidence: "manual" | "auto_high" | "auto_low" (optional)
}
```

**Main Flow**:
1. System loads SourceLink and parent Content
2. System updates SourceLink lifecycle fields
3. System recomputes and updates `Content.originHint` in the same transaction
4. System emits `source_link.updated` event
5. Return SourceLink and updated Content

**Post-conditions**:
- SourceLink lifecycle state is updated
- `Content.originHint` remains transactionally aligned with active source-link membership

**Error Handling**:
- If SourceLink not found: throw `NotFoundError`
- If lifecycle value is invalid: throw `ValidationError`

### UC-SRC-003: Upsert SectionSourceLink

**Purpose**: Attach source-specific section provenance and ordering evidence to a canonical ContentSection.

**Input**:
```
{
  sectionId: ContentSectionId
  sourceLinkId: SourceLinkId
  remoteContentSectionId: String
  remoteUrl: String (optional)
  remoteLabel: String (optional)
  sourceOrder: Integer (optional)
  linkStatus: "active" | "inactive" | "stale"
  confidence: "manual" | "auto_high" | "auto_low"
}
```

**Main Flow**:
1. System validates ContentSection and SourceLink exist
2. System validates the ContentSection belongs to the same Content as the SourceLink
3. System upserts SectionSourceLink by `(sourceLinkId, remoteContentSectionId)`
4. System stores `sourceOrder` as ordering evidence when provided
5. System emits `section_source_link.upserted` event
6. Return SectionSourceLink

**Post-conditions**:
- ContentSection-level source provenance exists or is updated
- First-canonical-section fallback can aggregate `sourceOrder` from active SectionSourceLinks

**Error Handling**:
- If ContentSection or SourceLink not found: throw `NotFoundError`
- If ContentSection/SourceLink belong to different Contents: throw `ValidationError`

---

## Reader Management Use Cases

### Core+DB Contract

Corrected target use-case mapping for the current core slice. Runtime implementation may lag schema-repair fields such as `ReadingSession.unitId` authority until a dedicated implementation catch-up slice lands:
- ResolveReaderTarget (internal resolution step within OpenReader)
- OpenReader
- UpdateReaderPosition

### UC-005: Open Reader

**Purpose**: Resolve a canonical reader target and return the section, ordered unit list, and active unit order for display.

**Actors**: User, System, ReaderUI

**Pre-conditions**:
- Content exists

**Input**:
```
{
  contentId: ContentId
  sectionId: ContentSectionId (optional)
  unitIndex: Integer (optional, 0-based)
  unitId: ContentUnitId (optional)
  correlationId: String (optional, for diagnostics tracing)
}
```

**Main Flow**:
1. System resolves the reader target via the target resolution policy (see ResolveReaderTarget below)
2. System loads the resolved section
3. System loads all units for the resolved section
4. System loads the active ContentUnitOrder for the section (if any)
5. System resolves the ordered unit list using the unit display/read order policy (see ContentUnit Display/Read Order below)
6. System validates the resolved unit target maps to a unit entry in the ordered list
7. Return target, section, active unit order, and ordered unit entries

**Post-conditions**:
- No write to reading_sessions (read-only resolution; position writes are handled by UpdateReaderPosition)
- No modification to any persistent state

**Error Handling**:
- If content not found: return `NOT_FOUND`
- If target cannot be resolved: return `READER_UNRESOLVED_LOCAL_TARGET`
- If resolved section disappears between resolution and load: return `READER_UNRESOLVED_LOCAL_TARGET`
- If no units exist for resolved section: return `NOT_FOUND`
- If active ContentUnitOrder is incomplete: return `VALIDATION_ERROR`
- If resolved unit target does not map to a unit: return `READER_INVALID_POSITION`

**Output**:
```
{
  target: ReaderOpenTarget {
    contentId: ContentId
    sectionId: ContentSectionId
    unitId: ContentUnitId
    unitIndex: Integer (derived from ContentUnit)
    sourceKind: "local" | "remote"
    resolutionReason: "requested_unit" | "requested_section" | "saved_session" | "first_canonical_section"
  }
  section: ContentSection
  activeOrder: ContentUnitOrderWithItems
  units: List<ReaderUnitEntry { unit: ContentUnit, sortIndex: Integer }>
}
```

---

#### ResolveReaderTarget (internal resolution step of OpenReader)

**Purpose**: Determine the canonical section and unit index to open, applying a strict fallback policy. This is not a standalone use case — it is an internal step of OpenReader.

**Fallback order**:

1. **Requested unit** (when `unitId` is provided):
   - Load unit by `unitId` and its parent section.
   - If unit or section is not found, or the parent section's `contentId` does not match the requested `contentId` → emit diagnostics warning and return `READER_UNRESOLVED_LOCAL_TARGET`.
   - If `sectionId` is also provided and does not match the unit's parent section → return `READER_INVALID_POSITION`; explicit inputs must not conflict.
   - Otherwise: use this unit and derive `sectionId` + `unitIndex` from the unit row.
   - Resolution reason: `"requested_unit"`.

2. **Requested section** (when `sectionId` is provided and `unitId` is absent):
   - Load section by `sectionId`.
   - If section not found, or section's `contentId` does not match the requested `contentId` → emit diagnostics warning and return `READER_UNRESOLVED_LOCAL_TARGET`.
   - Otherwise: use this section. `unitIndex` defaults to `0` if not provided.
   - Resolution reason: `"requested_section"`.

3. **Saved session** (when no explicit unit/section target is provided and an active reader session exists for the content):
   - Load the active saved session for the content.
   - Load the unit referenced by `session.unitId` and derive its parent section and `unitIndex`.
   - Validate the saved unit target: if unit or section is not found, or the section's `contentId` does not match the requested `contentId` → `READER_UNRESOLVED_LOCAL_TARGET` (no silent repair).
   - If `session.sourceLinkId` is present but the source link is stale/deprecated, treat it as read-context evidence only and prefer active alternative SectionSourceLink/ContentUnit provenance when available; stale source context must not invalidate the canonical saved unit by itself.
   - Otherwise: use the derived section and unit index.
   - Resolution reason: `"saved_session"`.

4. **First canonical section** (when no explicit target is provided and no valid active saved session exists):
   - Load all sections for the content.
   - For each section, compute aggregated source order: the minimum `sourceOrder` value across active, non-null section source links (where `linkStatus`, `sourceLinkStatus`, and `sourcePlatformStatus` are all `"active"`). ContentSections with no qualifying source links have no aggregated source order.
   - Sort candidates by the following tuple (all ascending):
     1. Numbered sections first: sections with a valid decimal-string `sectionNumber` sort before those without.
     2. `sectionNumber` ASC using decimal/numeric comparison (numbered sections only).
     3. Aggregated source order ASC (present values sort before absent).
     4. `createdAt` ASC.
     5. `id` ASC (lexicographic, tie-break).
   - If no sections exist → `READER_UNRESOLVED_LOCAL_TARGET`.
   - Use the first unit in the first sorted section by `unitIndex` ascending; `unitId` is the persisted/open-target authority and `unitIndex` is derived from that ContentUnit.
   - Resolution reason: `"first_canonical_section"`.

**READER_UNRESOLVED_LOCAL_TARGET conditions**:
- Requested section not found or belongs to a different content.
- Requested unit not found or belongs to a different content through its section.
- Saved session unit not found or belongs to a different content through its section.
- No sections exist on the content (first-canonical fallback exhausted).

**Diagnostics**: Each `READER_UNRESOLVED_LOCAL_TARGET` outcome records a `reader.route.unresolved_target` diagnostics event at `warn` level with the specific `reason` field and `contentId`.

---

### UC-005b: Update Reader Position

**Purpose**: Persist the reader's current position in a content.

**Actors**: User, System, ReaderUI

**Pre-conditions**:
- Content exists
- ContentUnit exists and its ContentSection belongs to the content

**Input**:
```
{
  contentId: ContentId
  unitId: ContentUnitId
  sourceLinkId: SourceLinkId (optional, last read-source context)
  sessionState: "active" | "suspended" | "completed" | "abandoned" (optional, defaults to "active")
}
```

**Main Flow**:
1. System validates content exists
2. System loads `unitId` and its parent ContentSection
3. System validates the parent ContentSection belongs to the content
4. If `sourceLinkId` is provided, system validates it belongs to the same content
5. If an existing active session already has the same `unitId`, `sourceLinkId`, and requested `sessionState` → return the existing session with `status = "skipped_unchanged"`, no write
6. System upserts the reader session in `reading_sessions` with the new `unitId` position authority, optional read-source context, and lifecycle state
7. Return the persisted session

**Post-conditions**:
- `reading_sessions` record created or updated for the content
- No other tables are written; scope stays within the reader session persistence boundary
- Current persistence is last-write-wins within the local single-runtime model
- No multi-device conflict-resolution contract is defined in the current core slice

**Error Handling**:
- If content not found: return `NOT_FOUND`
- If `unitId` is not found: return `READER_INVALID_POSITION`
- If the referenced ContentUnit's ContentSection does not belong to content: return `READER_INVALID_POSITION`
- If `sourceLinkId` is provided but does not belong to content: return `READER_INVALID_POSITION`

**Output**:
```
{
  session: ReadingSession (persisted position)
  status: "written" | "skipped_unchanged"
}
```

---

### UC-006: Get Reader Position

**Purpose**: Retrieve current reader position for resuming.

**Actors**: User, System, ReaderUI

**Pre-conditions**:
- Content exists

**Input**:
```
{
  contentId: ContentId
}
```

**Main Flow**:
1. System retrieves the active ReadingSession for content
2. If not found: system returns NotFound and lets orchestration/reader target resolution choose creation behavior
3. Return ReadingSession

**Post-conditions**:
- ReadingSession unchanged (read-only)
- No modification to position (read-only operation)

**Error Handling**:
- If content not found: throw `NotFoundError`

**Output**:
```
{
  session: ReadingSession (current persisted position)
}
```

---

### UC-007: Clear Reader Position

**Status**: Planned Canonical

**Purpose**: Reset reader position to start.

**Actors**: User, System

**Pre-conditions**:
- Content exists

**Input**:
```
{
  contentId: ContentId
}
```

**Main Flow**:
1. System retrieves the active ReadingSession for the content
2. If no active session exists, system returns success with `status = "no_active_session"`
3. System marks the active session `sessionState = "abandoned"` in place; it does not hard-delete the lifecycle row
4. System emits `reader.position_cleared` event
5. Return the abandoned ReadingSession or no-op status

**Post-conditions**:
- No active ReadingSession remains for the content
- Historical ReadingSession lifecycle evidence is retained
- (Favorites are deferred — see "Favorites Management Use Cases"; no favorite side-effects exist in the active contract)

**Error Handling**:
- If content not found: throw `NotFoundError`

**Output**:
```
{
  session: ReadingSession (abandoned, optional when no active session existed)
  status: "abandoned" | "no_active_session"
  event: DiagnosticsEvent (eventName: "reader.position_cleared")
}
```

---

## ContentUnit Display/Read Order

When OpenReader resolves the ordered list of units for a section, it applies the following policy:

**Primary path — active ContentUnitOrder exists**:
- Use the `ContentUnitOrderWithItems` whose `ContentUnitOrder.status = "active"` for the section.
- A ContentUnitOrder is considered **complete** when all of the following hold:
  - `unitOrderItems.length` equals the total number of units in the section.
  - Every item references a unit that exists in the resolved section (no dangling unit references).
  - Every unit in the section appears in exactly one item (full coverage, no duplicates).
  - All `sortOrder` / `sortIndex` values among items are unique (sort-order gaps are allowed).
- If the active ContentUnitOrder is **incomplete** (any of the above conditions are violated): return `VALIDATION_ERROR`. There is no silent fallback when an active order exists but is incomplete.

**Fallback path — no active ContentUnitOrder**:
- Use a synthetic source order: units sorted by `unitIndex` ASC.
- This fallback is only applied when there is no active ContentUnitOrder at all (null result from the repository).

---

## ContentUnit Asset Availability

OpenReader returns canonical unit rows and read order; byte availability is resolved by the storage/image-loading path.

Rules:
- `ContentUnit.storageObjectId = null` means no local storage object has been assigned yet.
- For remote sections, OpenReader must call `UC-REMOTE-001` from `07_FEATURES.md` before resolving read order if canonical ContentUnit rows have not been materialized yet.
- A materialized remote unit with `storageObjectId = null` may be served by source-runtime remote fetch through PluginProxy when active SourceLink/SectionSourceLink provenance exists.
- `ContentUnit.storageObjectId != null` does not guarantee readable bytes. The loader must resolve StoragePlacements and require at least one placement whose role/status is readable for the current backend policy.
- If no readable placement exists, the loader returns `STORAGE_OBJECT_UNAVAILABLE` or an explicit placeholder/retry state. It must not treat a StorageObject row by itself as success.
- Remote fallback from stale/missing local bytes must be a deliberate source-runtime decision using SourceLink/SectionSourceLink provenance, not an implicit storage lookup side effect.

---

## User Collection Management Use Cases

> **Planned Canonical — not current core implementation**
>
> UserCollection and UserCollectionItem define user-owned cross-platform grouping. They are separate from SourceLink identity merge/provenance and from source account favorite state.

### UC-COL-001: Create User Collection

**Purpose**: Create a user-defined grouping of contents.

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

### UC-COL-002: Add Content to Collection

**Purpose**: Add a content from any platform/source to a user collection.

**Input**:
```
{
  collectionId: UserCollectionId
  contentId: ContentId
  sortIndex: Integer (optional; required for exact manual insertion)
  pinnedAt: Timestamp (optional)
  allowRemoved: Boolean (optional, default false)
}
```

**Main Flow**:
1. System validates collection and content exist
2. If the Content has `libraryStatus = "removed"` and `allowRemoved` is not true, system rejects the add
3. System rejects duplicate `(collectionId, contentId)` membership
4. System assigns or shifts `sortIndex` atomically for manual order
5. System creates UserCollectionItem
6. System emits `collection.item_added` event
7. Return UserCollectionItem

**Post-conditions**:
- Content is a member of the collection
- Removed contents may be added only when the caller explicitly allows removed-library items

**Error Handling**:
- If collection or content not found: throw `NotFoundError`
- If content is removed and `allowRemoved` is not true: throw `ValidationError`
- If membership already exists: throw `DuplicateError`
- If sort index conflicts and cannot be repaired atomically: throw `ValidationError`

### UC-COL-003: Reorder Collection Items

**Purpose**: Persist manual order for collection membership.

**Input**:
```
{
  collectionId: UserCollectionId
  orderedContentIds: List<ContentId>
}
```

**Main Flow**:
1. System validates collection exists
2. System validates the supplied content IDs exactly match current membership with no duplicates or omissions
3. System updates all affected UserCollectionItem `sortIndex` values in one transaction
4. System sets or preserves `UserCollection.sortOrder = "manual"`
5. System emits `collection.reordered` event
6. Return ordered items

**Error Handling**:
- If collection not found: throw `NotFoundError`
- If membership list is incomplete or contains unknown contents: throw `ValidationError`

### UC-COL-003b: Move Collection Item

**Purpose**: Move one content within a manual collection order without sending the full membership list.

**Input**:
```
{
  collectionId: UserCollectionId
  contentId: ContentId
  afterContentId: ContentId (optional; null/absent means move to start)
}
```

**Main Flow**:
1. System validates collection exists
2. System validates `contentId` is a current member of the collection
3. If `afterContentId` is provided, system validates it is a different current member of the same collection
4. System moves the item to the requested position and reassigns affected `sortIndex` values atomically
5. System sets or preserves `UserCollection.sortOrder = "manual"`
6. System emits `collection.item_moved` event
7. Return ordered items or the moved item plus its new neighbors

**Error Handling**:
- If collection or item not found: throw `NotFoundError`
- If `afterContentId` is unknown, belongs to another collection, or equals `contentId`: throw `ValidationError`

### UC-COL-004: List Collection Contents

**Purpose**: Read contents inside a collection using the collection's sort policy.

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
2. System loads UserCollectionItems and joined Contents
3. Unless `includeRemoved = true`, filter contents whose `libraryStatus = "removed"`
4. Apply collection sort policy:
   - `manual`: `UserCollectionItem.sortIndex` ASC
   - `title`: current primary title ASC
   - `updated_at`: Content/metadata update timestamp DESC
   - `last_read`: ReadingSession `updatedAt` DESC, unread last
5. Return paginated items and contents

**Error Handling**:
- If collection not found: throw `NotFoundError`

---

## Favorites Management Use Cases

> **Not Implemented — current core pass**
>
> Favorite schema, domain model, ports, and exports are absent from the current runtime/core canonical slice. UC-008 through UC-010 below are retained as documentation of intended future behavior only. They carry no implementation authority and should not be treated as active contracts until a core favorites contract is explicitly introduced.

### Deferred/Legacy

### UC-008: Mark Content as Favorite

**Purpose**: Add content to user's favorites list.

**Actors**: User, System

**Pre-conditions**:
- Content exists
- Content not already favorited

**Input**:
```
{
  contentId: ContentId
}
```

**Main Flow**:
1. System retrieves Content
2. System checks if already favorited → idempotent, return existing Favorite
3. System creates Favorite with `marked_at = CURRENT_TIMESTAMP`
4. System emits `favorite.marked` event
5. Return Favorite

**Post-conditions**:
- Favorite record created
- `marked_at` timestamp set
- `last_accessed_at` initialized to null

**Error Handling**:
- If content not found: throw `NotFoundError`

**Output**:
```
{
  favorite: Favorite (newly created)
  event: DiagnosticsEvent (eventName: "favorite.marked")
}
```

---

### UC-009: Unmark Content as Favorite

**Purpose**: Remove content from favorites.

**Actors**: User, System

**Pre-conditions**:
- Content is favorited

**Input**:
```
{
  contentId: ContentId
}
```

**Main Flow**:
1. System retrieves Favorite
2. System deletes Favorite
3. System emits `favorite.unmarked` event
4. Return success

**Post-conditions**:
- Favorite record deleted
- Content still exists (not deleted)
- Reader position still exists

**Error Handling**:
- If content not found: throw `NotFoundError`
- If not favorited: throw `NotFoundError`

**Output**:
```
{
  success: Boolean
  contentId: ContentId
  event: DiagnosticsEvent (eventName: "favorite.unmarked")
}
```

---

### UC-010: List Favorites

**Purpose**: Retrieve user's favorited contents.

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
2. For each Favorite: retrieve full Content with metadata
3. Return list of Favorites with associated Contents

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
    content: Content
  }>
  totalCount: Integer
  limit: Integer
  offset: Integer
}
```

---

## ContentSection & ContentUnit Management Use Cases

### Deferred/Legacy

### UC-011: Create ContentSections from Import

**Purpose**: Create ordered sections from imported files.

**Actors**: System, ImportProcess

**Pre-conditions**:
- ImportBatch exists with files list
- All files are images or valid containers

**Input**:
```
{
  importBatchId: ImportBatchId
  groupingStrategy: String ("single_section" | "by_folder" | "by_file")
  sectionNumbering: String ("sequential" | "by_filename")
  sectionKind: String ("chapter" | "episode" | "oneshot" | "volume" | "season" | "group" | "section" | "entry" | "article" | "part", optional, default "chapter" for visual content / "section" for text content)
}
```

**Main Flow**:
1. System retrieves ImportBatch and files
2. System validates `sectionKind`; unit-bearing visual imports normally use `chapter`, `episode`, or `oneshot` (text imports use `section`, `entry`, `article`, or `part`)
3. If `sectionKind` is a container kind (`season`, `volume`, or `group`) and the resolved grouping would assign readable ContentUnits directly to that node, system rejects with `ValidationError` unless the import plan also creates child unit-bearing sections
4. Based on `groupingStrategy`:
   - `single_section`: Create one section with all units
   - `by_folder`: Create section per folder
   - `by_file`: Create section per file (archive or container)
5. Based on `sectionNumbering`:
   - `sequential`: normalized decimal strings such as `"1"`, `"2"`, `"3"`
   - `by_filename`: extract and normalize decimal strings such as `"1.5"`
6. For each unit-bearing imported unit: create a ContentSection with a unit-bearing `sectionKind` and create all units in order
7. If import grouping creates container nodes (`volume`, `season`, or `group`), those nodes may own children but must not own readable ContentUnits directly
8. Initialize section unit ordering from the canonical source sequence
9. System emits `sections.created` event
10. Return created ContentSections

**Post-conditions**:
- ContentSections created with sequential numbers
- ContentUnits created in order
- Resolved unit order defaults to the canonical source sequence (`unitIndex` ascending); implementation may satisfy this through synthetic fallback or explicit order-row materialization

**Error Handling**:
- If ImportBatch not found: throw `NotFoundError`
- If invalid strategy: throw `ValidationError`
- If invalid or structurally incompatible `sectionKind`: throw `ValidationError`
- If parsing fails: throw `ValidationError`

**Output**:
```
{
  sectionsCreated: Integer
  sections: List<ContentSection>
  unitsPerContentSection: List<Integer>
  event: DiagnosticsEvent (eventName: "sections.created")
}
```

---

### UC-012: Reorder ContentUnits in ContentSection

**Purpose**: Set custom unit ordering for a section.

**Actors**: User, System

**Pre-conditions**:
- ContentSection exists
- All unit IDs belong to section

**Input**:
```
{
  sectionId: ContentSectionId
  unitIds: List<ContentUnitId> (user-specified order)
}
```

**Main Flow**:
1. System retrieves ContentSection
2. System validates all unit IDs exist in section
3. System validates all section units are included
4. System updates ContentUnitOrder with `order_type = 'user_override'`
5. System stores user unit order through `ContentUnitOrder` + `ContentUnitOrderItem` entries (not delimited strings)
6. System emits `section.units_reordered` event
7. Return updated ContentUnitOrder

**Post-conditions**:
- ContentUnitOrder updated with user override
- Reader position may need adjustment if current unit moved
- `updated_at` timestamp refreshed

**Error Handling**:
- If section not found: throw `NotFoundError`
- If unit IDs invalid: throw `ValidationError`
- If not all units included: throw `ValidationError`

**Output**:
```
{
  unitOrder: ContentUnitOrder
  newOrder: List<ContentUnitId>
  event: DiagnosticsEvent (eventName: "section.units_reordered")
}
```

---

## Deferred CRUD / Management Use Case Appendix

These operations are intentionally deferred. Their absence from the current build order must not be interpreted as permission to mutate the underlying tables ad hoc.

### Deferred: ContentUnit CRUD Outside Import
- Create/update/delete individual ContentUnits after import
- Must preserve unit-order completeness, reading-session references, cover lifecycle, and storage availability invariants

### Deferred: SourceLink Deletion
- Detach or remove Content-level provenance links
- Must recompute `Content.originHint` in the same transaction
- Must cancel queued/active download tasks for the deleted source link in the same transaction; terminal download history may retain `sourceLinkId = null` evidence
- Must define whether historical rejected/stale evidence is retained or hard-deleted

### Deferred: SectionSourceLink Deletion
- Detach or remove ContentSection-level provenance links
- Must recompute source-order fallback evidence when an active source-order link is removed

### Deferred: ContentRelationship CRUD
- Create/update/delete ContentRelationship rows and review ContentRelationshipProposal rows
- Must preserve directed-edge semantics and avoid implicit reverse-edge writes unless a future contract explicitly adds them

### Deferred: Tag Management
- Canonical tag CRUD, source tag mapping CRUD, user tag CRUD, and content-user-tag assignment
- Must define tag key normalization, collision behavior, and deletion/reassignment semantics before implementation

### Deferred: ContentSection CRUD Outside Import
- Create standalone sections, delete sections, reparent sections, and change section kind/number/label
- Must choose explicit subtree delete, child reparent, or reject-if-children behavior; silent child promotion remains invalid

---

## Search & Browse Use Cases

### Deferred/Legacy

### UC-013: Search Contents

**Purpose**: Full-text search across contents.

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
2. Unless `includeRemoved = true`, system filters out contents with `libraryStatus = "removed"`
3. System orders results by relevance
4. System paginates results
5. For each content: retrieve metadata and reader session
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
  results: List<Content>
  totalMatches: Integer
  query: String
  limit: Integer
  offset: Integer
}
```

Diagnostics note:
- Raw query may be returned to caller, but diagnostics should persist `queryHash` and optional sanitized preview.

---

### UC-014: List All Contents

**Purpose**: Browse all contents in library.

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
1. System retrieves Contents, excluding `libraryStatus = "removed"` unless `includeRemoved = true`
2. System sorts by specified field
3. System paginates
4. For each content: retrieve metadata, reader session (favorite status deferred — see Favorites Management Use Cases)
5. Return paginated contents

**Post-conditions**:
- No modification
- Read-only operation

**Error Handling**:
- If invalid sortBy: throw `ValidationError`
- Returns empty list if no contents

**Output**:
```
{
  contents: List<Content>
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
  eventName: String (e.g., "content.created", "reader.position_changed")
  correlationId: String (optional trace ID)
  boundary: String (optional)
  authority: String (optional)
  contentId: String (optional)
  sourcePlatformId: String (optional)
  action: String (optional)
  payload: Object (event-specific data)
```

**DiagnosticsEvent Examples**:
```
{
  level: "info",
  channel: "content",
  eventName: "content.created",
  action: "created",
  contentId: "...",
  payload: { normalizedTitle }
}

{
  level: "info",
  channel: "reader.position",
  eventName: "reader.position_changed",
  action: "updated",
  contentId: "...",
  payload: { unitId, sectionId, unitIndex }
}
```

---

## Use Case Error Matrix

| Use Case | Status | NotFound | Duplicate | IdempotencyConflict | Validation | ReaderUnresolved | ReaderInvalidPos | Permission* | Storage |
|----------|--------|----------|-----------|---------------------|------------|-----------------|-----------------|-------------|---------|
| Create Content | Implemented | - | - | X | X | - | - | - | X |
| Import Content | Deferred/Legacy | X | X | - | X | - | - | - | X |
| Update Metadata | Implemented | X | - | - | X | - | - | - | X |
| Remove Content | Planned Canonical | X | - | - | X | - | - | X | X |
| Permanently Delete Content | Planned Canonical | X | - | - | X | - | - | X | X |
| Add SourceLink | Planned Canonical | X | X | - | X | - | - | - | X |
| Update SourceLink Status | Planned Canonical | X | - | - | X | - | - | - | X |
| Upsert SectionSourceLink | Planned Canonical | X | - | - | X | - | - | - | X |
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
| Create ContentSections | Deferred/Legacy | X | - | - | X | - | - | - | X |
| Reorder ContentUnits | Deferred/Legacy | X | - | - | X | - | - | - | X |
| Search Contents | Deferred/Legacy | - | - | - | X | - | - | - | X |
| List Contents | Deferred/Legacy | - | - | - | X | - | - | - | - |

\* `Permission` is adapter/auth-layer concern in current core slice, not core-owned domain authority.

`ReaderUnresolved` = `READER_UNRESOLVED_LOCAL_TARGET` — emitted when the resolution policy exhausts all fallbacks or encounters a stale/invalid saved target.

`ReaderInvalidPos` = `READER_INVALID_POSITION` — emitted when a position write or unit lookup references a section/unit that exists but does not match the requested coordinates.
