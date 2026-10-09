# v2 One-Time Legacy Venera Distributed-Data Import

> **Status: design companion — 2026-10-10.** User-initiated, one-way **data import from old Venera to a fresh v2 canonical database**. The old executable runtime and schemas are not part of the new runtime. **Domain entities and invariants are authoritative in 01_ENTITIES; reference target DDL in 02_DATABASE_SCHEMA; UC-LGI-001–004 in 03_USE_CASES; application ports in 04; category behavior in 07; diagnostics in 09; phase gates in 11.** This document retains inspected old-format evidence, threat cases and acceptance tests; no runtime has yet been implemented.
>
> **Hard scope:** only `local.db`, `history.db`, `local_favorite.db`, `appdata.json` and `implicitData.json` may be imported as old-Venera metadata inputs. Old Unified Store `venera.db` is **explicitly unsupported** and **must never** be used as a fallback. The new v2 `data/venera.db` is the **destination**, not a legacy input.
>
> **Canonical dependencies:** [01_ENTITIES.md](01_ENTITIES.md), [02_DATABASE_SCHEMA.md](02_DATABASE_SCHEMA.md), [03_USE_CASES.md](03_USE_CASES.md), [10_MVP_SCOPE.md](10_MVP_SCOPE.md), [11_MILESTONES.md](11_MILESTONES.md). This proposal does not create a second Reader Position authority or loosen the ContentUnitOrder completeness invariant.

> **L0 code evidence (2026-10-10):** `tools/legacy-import/` now contains Node 22.16 read-only five-file preview, Linux/macOS-Docker reference sandbox with disabled network/read-only mounts and bounded resources, trusted-host result sanitization, pure dataset-scoped record identity keys, fixture tests and CI smoke. The result remains aggregate statistics only with `canCommit=false`. **Partially implemented:** `mapping-repository.mjs` uses the canonical v2 dataset/mapping DDL and tests persisted owner-scoped identity/idempotency, but must only be invoked after trusted user approval. **Host-side approval contract added (2026-10-10):** `approval-gate.mjs` validates exact input-role snapshot digests and a trusted user-gesture through injected host callbacks, then atomically persists the approved batch and, for a new legacy dataset, its dataset row. `mapping-repository.mjs` rejects missing/cancelled/wrong-owner/wrong-plan/wrong-role batches before record reservation. **L0 integration added:** sandboxed `export-snapshots.mjs` creates verified role snapshots, private temporary output is copied into a time-bounded, owner-/dataset-scoped in-memory lease, and the host signs off by revalidating that exact lease at Approval and each Mapping mutation. CI includes an actual Docker export and changed-original test. **Still missing:** real trusted UI/gesture-verification adapter, persistent crash-recovery-ready snapshot store, per-record snapshot provenance attestation, media grants, journal/receipt implementation, canonical Content import and platform security review. This gate alone does not authorize files/assets to be copied or replace product sandbox review. Docker image tag must be digest-pinned for production and selected-directory read-only mount is broader than per-file handles. The direct CLI is developer/debug only; no legacy user data was imported.

## 1. Strict source-format registry

| Exactly allowed input basename | Inspected legacy implementation | Allowed *categories* |
|---|---|---|
| `local.db` | `lib/legacy/foundation/db/local_comics_store.dart`, table `comics` | Local work metadata, chapters, page-file discovery **through separately authorized media roots**, covers, source tags as evidence |
| `history.db` | `lib/legacy/foundation/db/history_store.dart`, tables `history` and `image_favorites` | Historical reading rows; **separately** image-favorite evidence |
| `local_favorite.db` | `lib/legacy/foundation/db/favorites_store.dart`, legacy per-folder tables | Favorite collection names and order; comic-favorite membership/order |
| `appdata.json` | `lib/legacy/foundation/appdata.dart` | Explicitly allowlisted non-secret preferences |
| `implicitData.json` | `lib/legacy/foundation/appdata.dart` | Explicitly allowlisted non-secret typed fields; otherwise skip |

Input acceptance is keyed by **role and exact basename**, not extension alone. Only inspected table/column variants and JSON keys are parsed. Any unexpected old DB/JSON, including `syncdata.json`, all Unified Store files/tables, script binaries, raw account secrets and third-party cache indexes, is out of scope. Do not silently detect or add other inputs.

- The user selects the old data directory or named files. Missing optional files are reported as `SKIPPED_MISSING_INPUT`. The user-facing importer can operate on a subset; a requested but unsupported category is reported as **deferred**, not imported.
- A listed SQLite database's `-wal` and `-shm` journal sidecars may be used **only by SQLite itself** to obtain a consistent snapshot of *that one selected DB*. They are **not additional user-selectable metadata sources**, not separately parsed, and never added to the five-file registry.
- Image directories, CBZ archives and covers referred to by `local.db` are **media assets**, not metadata-input formats. Access requires a separately selected **local media root**; the legacy DB's absolute/relative paths alone confer no filesystem access.
- Neither the old Unified Store `venera.db` nor the fresh target `data/venera.db` may enter the source reader, including through symlinks, a renamed file masquerading as `local.db`, an automatic discovery path or a schema fallback. Check resolved file identity and table signature, not only the filename.
- No old JS source installation/execution, persisted cookies, website passwords, bearer/API tokens, OS keychain extraction or automatic network sign-in.

## 2. Boundary, workflow and preflight

~~~text
Trusted user intent
   -> Picker [strict 5 input roles + explicitly granted media roots]
   -> Source Snapshotter [read-only SQLite-consistent snapshot; bounded JSON copies]
   -> Isolated Legacy Parsers [known schema variants only; no old runtime imports]
   -> Normalizer [typed, non-executable ImportProposals]
   -> RecordIdentityMap [dataset-scoped stable keys; history/favorite joins]
   -> Identity/Position Reconciler + Conflict Analyzer
   -> DRY RUN report [all categories, deferred/ambiguous/skipped]
   -> User approves exact decisions
   -> Staged Asset Writer + Canonical V2 Use Cases
   -> Verify + Durable Receipt + Recovery/GC
~~~

**Preflight requirements:**

1. Prefer user closing old Venera. Open SQLite source read-only with no extension loading or untrusted SQL; obtain a **consistent database snapshot** using SQLite's backup API (or equivalent audited snapshot technique). Do **not** copy a live DB file by itself while WAL may hold committed data. If SQLite cannot safely snapshot the input (e.g. incomplete sidecars, live churn, locked source), emit `SOURCE_SNAPSHOT_UNAVAILABLE` and stop that file. Never force a checkpoint or write to the original.
2. Parse only the private snapshot; run `PRAGMA quick_check` and schema/signature verification on it. Run `foreign_key_check` where appropriate, but don't assume all old legacy formats enabled FKs. Never execute legacy triggers, user-defined functions, extensions or schema migrations. Harden SQLite adapter against attachment/virtual table/extension side effects; don't execute source-provided SQL.
3. Treat JSON as untrusted: size, nesting, UTF-8, object keys, string lengths, number ranges, prototype-key checks and schema-version limits. All parsing and file enumeration obey CPU, memory, row and disk quotas. Unsupported schema version is a per-input explicit error, **not** a prompt to run old Dart migration code.
4. For per-folder `local_favorite.db` tables, enumerate `sqlite_master`, reject internal/unexpected table shapes, validate column layout with `PRAGMA table_info`, and safely quote/escape identifier names in a reviewed adapter. Parameter binding protects **values**, not table names. Cap the number of folders/tables.
5. Each media asset path must be canonicalized, checked to lie inside an explicitly selected root, and opened without symlink traversal/TOCTOU escape (use suitable platform handle APIs or re-check the actual opened target). Do not follow an untrusted stored URL onto the network.
6. All snapshots and staging files live in app-private storage with bounded retention. Verify they are not the new v2 destination and never log original paths, titles or raw JSON. Destructive cleanup is confined to importer-owned private staging locations.

**No side effects during dry run:** no new Content rows, no active orders, no network, no downloaded plugin/translation packs, no vault credentials, no source file writes, and no background auto-login.

### Five-file L0 record attestation (implemented 2026-10-10)

Docker-isolated `export-snapshots.mjs` produces commitments from **the same inspected immutable snapshots**. `record-provenance.mjs` covers `local.db.comics`, `history.db.history`, `history.db.image_favorites`, dynamic folder memberships in `local_favorite.db` and only vetted `appdata.json.settings` keys. `implicitData.json` has an explicit **empty attestation**—no secret-bearing implicit key is eligible for Record Mapping.

Each proof is bound to the exact input snapshot SHA-256. Record identity includes the appropriate role, table, source type and favorite-folder scope. Host checks proof counts by file/category and validates unique keys; `reserveAfterApprovedPlan` requires an Approved Batch, live owner-bound Snapshot Lease and **exact Key + Record Digest** in that lease. Arbitrary SHA-256, changed source records and forged IDs are rejected.

**This is evidence-only, not data migration.** Attested records may be reserved for review, but remote source resolution, History → ContentUnit/ReadingSession, favorites → UserCollection, and preference application remain phase-gated and require separate explicit authorization. The old Unified Store `venera.db` remains unsupported, and no old website credentials or JS source code is imported. Production sandbox/host trust signoff and the end-user Wizard are still outstanding.

### L0 trusted terminal approval slice (2026-10-10)

`trusted-wizard.mjs` coordinates a host-only **evidence approval**, using the already inspected Docker Snapshot and private Lease. `trusted-gesture.mjs` uses a randomized challenge phrase bound to owner, dataset and Plan Digest; a real interactive TTY must collect it. A credential is an **opaque one-shot host object**, consumed on first verification, including rejection. The reference `wizard-console.mjs` refuses non-TTY/implicit approvals, requires a pre-existing fresh-v2 DB and does not import Content, ReaderSession, Favorites, images or Settings.

The Approved Batch now contains a schema-enforced `approval_scope='evidence_only'` and `policy_revision='l0-evidence-only-v1'`. A later Content importer **must never reuse** this metadata-evidence approval as consent to migrate user records or storage; future action scopes require their own reviewed contract and user confirmation. Failure/cancellation revokes the private Snapshot Lease; approval expiry or app restart never silently reopens original files. Memory leases are bounded and auto-expire even while idle.

This TTY prototype **is not the final end-user Desktop UI, OS identity authentication, or proof of physical presence**. Final Desktop clients need a trusted native main-process consent surface and authenticated principal; ordinary renderer events, plugin JS and remote API flags cannot authorize an import. All L1/L2/M1/M2 data import gates remain open.

## 3. Dataset / Record Identity vs Batch Evidence (P0)

An input snapshot digest and a legacy record identity solve **different** problems. They must **not** be conflated.

- **ImportBatch** is one user-approved attempt, with a random batch ID, the selected input-role manifest, content hashes of consistent snapshots, options/policy version and result counters. Its digest is a *batch dedupe/diagnostic signal*, not the identity of comics.
- **ImportDatasetScope** is an immutable local identity for **one old Venera installation/profile**. Create it at first import and persist it. Reopening or moving the same five files should reuse this dataset only after trusted matching/user confirmation; two separate installations with overlapping legacy IDs must have **different** dataset scopes. Neither filesystem path nor a filename-only hash is a reliable dataset identity.
- **LegacyRecordKey** is deterministic **inside dataset scope**, built from `(datasetScopeId, fileRole, tableKind, scopeName?, legacyType?, legacyId)` after lossless type normalization. Table/folder name is part of favorite membership key; `comic_type + id` distinguishes local works, `type + id` distinguishes history, `source_key + id` distinguishes image favorites. For settings use `(fileRole, jsonNamespace, propertyKey)`. Avoid title-only, page ordinal-only and path-only IDs.
- **LegacyRecordMapping** persists `LegacyRecordKey → canonical target(s) + mapping status + source-record digest + verified evidence`. A changed `appdata.json` snapshot cannot allocate new IDs for already imported comics. A record's updated metadata is a **reconcile/update suggestion**, not a new Content by default.
- **Exact same record**: skip/unchanged. **Changed same key**: report a diff and apply reviewed update policy. **New key**: create/review. **Same key with contradictory identity evidence**: conflict; never mutate canonical IDs silently.
- **One-time semantics**: no perpetual legacy-data synchronization. Manual explicit re-run and crash recovery are supported and **idempotent**; repeated import is not permission to overwrite new v2 edits.

### Proposed staging/receipt model (logical; not executable DDL)

| Record | Fields and uniqueness | Lifecycle |
|---|---|---|
| `LegacyImportDataset` | `id`, user scope, user-confirmed source identity label, createdAt | active / archived |
| `LegacyImportBatch` | `id`, `datasetId`, selected file roles, snapshot digests, policy/schema revision, timestamps, counters | selected → snapshotted → previewed → approved → applying → verified / partial / failed / cancelled |
| `LegacyRecordMapping` | unique `(datasetId,fileRole,tableKind,scopeName,legacyType,legacyId)`; source record digest, target kind/ID and evidence revision | mapped / unchanged / changed_pending / conflict / tombstoned |
| `LegacyUnresolvedRecord` | `id`, `batchId`, `recordMappingKey`, bounded typed review evidence, candidate target IDs (not raw payload), reason, next eligible milestone, disposition | pending → resolved / skipped / dismissed; reviewer decisions audited |
| `LegacyImportReceipt` | `batchId`, committed target mappings, category status/counters, artifact manifest, verification result, policy revision | durable terminal summary, including partial outcomes |
| `LegacyAssetJournal` | importer-owned blob path refs, digest, target StorageObject ID, promotion/DB states, cleanup marker | staged → verified → promoted → committed / gc_pending |

**Schema gates:** nullable members in composite identity keys require canonical non-null sentinels or explicit normalized identity serialization before applying UNIQUE indexes; SQLite NULL semantics can otherwise permit duplicates. Foreign keys, owner scoping, CHECKs, retention constraints and unique indexes belong in `02_DATABASE_SCHEMA.md` upon adoption. Review evidence may contain private titles or folder names; keep in local protected staging, restrict UI access, set expiry/cleanup policy and never emit raw evidence in logs. Do not store passwords, sessions or raw appdata/implicit JSON blobs as "unresolved" evidence.

## 4. Category mapping and staged dependencies

### 4.1 Local comics from local.db

Observed old fields include `comics(id, comic_type, title, subtitle, tags, directory, chapters, cover, downloadedChapters, created_at)`. Check the inspected input schema instead of assuming every build has exactly those columns.

1. Derive a dataset-scoped legacy work key from `(comic_type,id)`; map to a **new UUID** `ContentId`. Do not import old IDs as canonical.
2. Parse `chapters` with a tested, bounded legacy-shape adapter. Establish section hierarchy and ordered page-file evidence. Create fresh `ContentSectionId` and `ContentUnitId` only for verified readable media or separately reviewed valid content; derive active `ContentUnitOrder` covering **exactly all existing units** in the section.
3. Copy or securely adopt user-approved media only. A missing media root can produce a clearly marked **metadata-only/unresolved** Content on explicit choice; do not synthesize unavailable page units, assign broken StoragePlacements, fabricate a cover, or create an incomplete active order. Such content cannot claim to be readable.
4. Source `tags`, `downloadedChapters` and cover path are **evidence and candidate attributes**, not automatically valid v2 taxonomy labels or completed download state. Preserve bounded, non-sensitive tag evidence in staging; defer canonical tag mapping/UI to **M2**. Never mark a download complete without verified owned storage.
5. Content with existing v2 identity is reconciled by verified legacy key, asset digest/evidence or user decision; title similarity only produces review suggestions. `repair_verified_same_asset` must preserve canonical ContentId and any saved UnitId whose bytes remain provably the same.

### 4.2 History.db: reading history versus image favorites

**Different table, different destination:**

- `history` rows include `id, title, subtitle, cover, time, type, ep, page, readEpisode, max_page, chapter_group`. They are **historical evidence**, not automatically a new active ReadingSession. Historical timestamps stay as source evidence. A new active session may only be created/updated through the canonical Reader Position use case with verified Unit identity, and never overwrite an already active v2 session without explicit conflict resolution.
- `image_favorites` rows include `id, title, sub_title, author, tags, translated_tags, time, max_page, source_key, image_favorites_ep, other`. These are **page/image favorite candidates**, not the same as favorite comics or `UserCollection` membership. Preserve only bounded allowlisted non-secret evidence in staging. Do **not** silently insert them into UserCollections. A later explicit image-favorite feature/model can adopt them; until then report `DEFERRED_IMAGE_FAVORITES`.
- Missing provider/plugin means remote work history or image favorites cannot be interpreted as readable local units: leave `SOURCE_UNRESOLVED` staging without creating a fake SourceLink or triggering website requests.

### 4.3 local_favorite.db: collection folders and membership

- The old DB uses user-named per-folder tables; expected columns include `id, name, author, type, tags, cover_path, time, translated_tags, display_order`, with potential optional fields. Resolve schema for each valid folder, and preserve folder order when evidence permits.
- Map each folder into `UserCollection` **only after M2**, preserving a dataset-scoped mapping and deterministic display order. Create `UserCollectionItem` **only** if a real canonical `ContentId` has been matched.
- Favorite items with account-only work references, conflicting `(type,id)`, deleted media or unavailable provider remain `LegacyUnresolvedRecord`. The imported folder can exist even when some items are pending; show partial membership accurately.
- Tags and tag translations remain evidence until M2 taxonomy mapping. No HTML rendering of unsanitized folder names or tags.

### 4.4 JSON settings

- `appdata.json`: inspect known `settings` and other validated shapes, but import **only individually allowlisted** settings with proven semantics and type conversion. Unknown reader gestures/legacy UI flags are skipped or previewed; don't copy arbitrary configuration or all key/value pairs.
- `implicitData.json`: default **skip**; import only reviewed namespace/key/type combinations with documented v2 meaning. If none are approved for an implementation release, report zero imported and explicit skipped counts.
- No raw HTTP headers, cookies, JWTs, passwords, API keys, device fingerprints, source-script code, unrestricted URLs or plugin account state may be imported. No automatic registration of source plugins or credential profiles. Reconnection after M3 uses new trusted UI + AuthBroker.

## 5. Reading position reconciliation (P0)

**Invariant:** `ReadingSession.unitId` is the only persisted v2 resume authority. Old `history.ep`/`page`/`readEpisode`/`chapter_group` fields are **untrusted, version-specific evidence**. Never assign new UUIDs from old integers or assume 0-based versus 1-based semantics without verified evidence.

### Evidence and decision algorithm

1. **Work identity:** match the old history `(type,id)` to an already mapped local work `(comic_type,id)` **only where the inspected legacy type semantics prove the match**; for remote history require a verified provider/source identity mapping (M3) and appropriate account scope. A title, cover URL or candidate source key alone cannot authorize auto-match.
2. **Section identity:** from the verified work, obtain section candidates using validated `chapters` structure, source/chapter identifiers and `readEpisode` only where the old version's encoding has been established by fixture/source research. Check `chapter_group` and `ep` semantics **for that specific old schema**; never treat them as a new section UUID or blindly apply an offset.
3. **Unit identity:** establish original page ordering from verified asset manifests (ordered filenames, file hashes and, if available, original page identity evidence). Determine index base from a **versioned mapping rule**, or corroborating data; test both possible offsets only to **detect ambiguity**, not to auto-pick whichever resolves.
4. **Validate** the unique candidate's work/section ownership, existing active order coverage, actual page bytes/asset identity where available, nonnegative in-range ordinal and any conflicting source fields. If two pages are plausible, changed order cannot be proven or media is missing, reject auto-resolution.
5. **Disposition:** classify as `VERIFIED_UNIT` (one proven target), `REVIEW_REQUIRED` (one or more plausible but insufficiently proved), `UNRESOLVED` (missing work/section/assets/source), or `UNSUPPORTED_FORMAT` (legacy encoding unknown). These are **categorical states**, not fabricated numeric confidence percentages.
6. **Write:** only `VERIFIED_UNIT` can propose a canonical Reader Position update. Commit through `UC-005b Update Reader Position` (or a future explicitly reviewed import-aware command using the same invariants). An existing active v2 session takes precedence absent explicit user choice; review may choose keep_current / use_verified_legacy. Preserve old timestamp as historical evidence; don't forge `reading_sessions.updated_at`.

### Cases that must not silently pass

- `ep=3,page=4` can mean different items under old group/index policies: if mapping not verified, mark `REVIEW_REQUIRED`.
- `page=0` vs `page=1` cannot prove index base by itself.
- Two chapters have identical titles or moved/reordered files: titles/ordinals are not identity evidence.
- A source-only history record with no installed source cannot gain an active reader position.
- Repeating the same import while the user has advanced in v2 must not rewind the session.

## 6. Filesystem + DB commit, crash recovery and idempotent retry (P0)

**SQLite transactions do not cover filesystem writes.** Never claim copying/promoting image files and inserting StorageObject/Placement rows is one atomic SQLite transaction. Use a durable, importer-controlled journal and a recoverable **two-resource commit protocol**.

~~~text
PREFLIGHT / DRY RUN — no persistent v2 domain mutation
  -> user approves plan, asset grant and conflict choices
  -> create durable batch + per-record intent + asset journal
  -> STAGE assets in private bounded directory; write+hash+fsync where feasible
  -> VERIFY exact asset bytes, media type, count and complete proposed order
  -> DB txn A: record pending intent + reserved deterministic storage identifiers
  -> PROMOTE verified assets to final managed storage with atomic same-volume rename
     (or verified copy+fsync+rename if crossing devices)
  -> DB txn B: assert promoted files are readable, atomically write/activate
     canonical Content/Section/Units/full Order/StorageObject+Placement,
     stable legacy mappings, import progress and receipt segment
  -> POSTCOMMIT verify referenced bytes and mapping; finalize receipt
  -> GC only importer-owned unreferenced staging/orphan files under retention rules
~~~

**No active/unreadable state:** DB transaction B is the visibility boundary. Before it commits, nothing new is exposed as a readable v2 content subtree. A fully imported section's active order must contain every canonical Unit exactly once. A per-content commit is acceptable; the whole batch can be **partial**, but per-content subtrees cannot be half-active. Canonical references must point to readable verified assets at the time of activation.

**Crash windows and recovery:**

| Crash point | Next run recovery |
|---|---|
| Before intent | discard private temporary snapshots/staging after policy retention; no v2 content change |
| After pending intent, before any promotion | revalidate staged hashes, resume promotion or cancel/GC pending intent |
| After asset promotion, before DB txn B | re-read journal, verify promoted files, finish *same intended mapping* or GC verified orphan after lease/retention; never allocate new ContentIds |
| During DB txn B | SQLite rolls back or commits the whole domain subtree; inspect journal and committed mapping, then reconcile; never assume counters reflect success |
| After DB commit, before receipt finalized | verify committed mapping/files, recover receipt from durable state, mark verified/partial; don't reimport rows |
| Partial batch / retry with updated JSON snapshot | per-record mapping wins; only changed/new settings considered, prior comic IDs unchanged |

- Promotion operations are **idempotent** and target paths are deterministic/unique per allocated StorageObject; verify checksum before accepting an already existing file. Avoid overwriting a file owned by another content/version.
- Cross-device promotion must use staging on the target volume or a carefully fsync-verified copy/rename protocol; do not claim a cross-volume rename is atomic.
- Cancellation is safe before visible per-content commit; after commit it records partial completion and never deletes canonical data without a separate explicit undo command. A reversible whole-batch rollback is **not promised**.
- Recovery/garbage collection is limited to importer-owned paths and files proven unreferenced by canonical StoragePlacements; no automatic deletion of legacy originals or user-selected media roots.
- Receipt and counts are derived from committed records, not merely attempted operations. DB uniqueness and operation idempotency prevent duplicate Content/Order/History/Collection on retries. Re-read stored auth-free import policy/review decisions only from trusted state, not reconstructed from untrusted JSON.

## 7. UX, retention and typed outcomes

~~~text
Select permitted files and local media roots
 -> Snapshot and format validation (source never modified)
 -> Inspect identities, category readiness and media availability
 -> Dry-run preview (counts + exact conflict reasons + would-be updates)
 -> User chooses skip / keep_both / verified_merge / metadata_only / defer
 -> Commit approved independent content subtrees
 -> Verify assets/orders/mappings and show receipt
 -> Review pending identity/position/image-favorite records separately
~~~

- UI reports for every selected file: `IMPORTED`, `UNCHANGED`, `SKIPPED_MISSING_INPUT`, `INVALID_FORMAT`, `DEFERRED_DEPENDENCY`, `REVIEW_REQUIRED`, `FAILED` and a **batch-level** `PARTIAL` or `VERIFIED`. Errors are actionable and never mislabeled success.
- Data that is **unresolved** is **not** the same as "not imported"; preserve a bounded staging record with reason, candidate IDs and milestone readiness. Only an explicit review can resolve it; never silently retry provider/login/network operations.
- Display private titles and old paths only in a trusted local review UI; diagnostics contain category, counts, error codes and opaque batch refs—not raw paths, raw JSON, credentials or source-supplied markup.
- Configure retention of snapshots/staged blobs separately from durable mappings/receipts; do not delete unresolved evidence prematurely, and allow user to purge import evidence without deleting canonically imported works.
- Legacy originals and local media are **never changed** by import. No network, Hosted upload or automatic account migration as part of one-time import.

## 8. Delivery gates (independent of new runtime implementation)

- **L0** (after M0 foundations): fixed five-file registry; old-format fixtures; read-only WAL-safe SQLite snapshots; bounded JSON adapters; dataset/record identity and dry-run contracts; security tests.
- **L1** (after M1 Reader/use cases): local work/media import, verified unit-order creation, safe `history.db` position matching. **Tag strings remain evidence**, not canonical taxonomy writes.
- **L2** (after M2 UserCollection and tag contracts): `local_favorite.db` folder/membership, reconciled tags/allowlisted appdata/implicit settings. Image favorites remain staged unless a dedicated image-favorite entity exists.
- **L3** (after M3 SourceInstance/AccountProfile): optional reviewed source-only historical reference resolution. No website login, remote fetch or plugin installation by default.
- **User-facing five-file completion promise:** only when every requested category handler is ready. Otherwise report **partial/deferred** and preserve evidence for explicit later review. No silent re-scan or background synchronization.

## 9. Acceptance tests: fixtures and negative cases (no old runtime execution)

1. `local.db` with 2 local works, chapter grouping, filesystem order and readable media → distinct new UUID identities, verified StoragePlacements, complete active orders.
2. Reimport same dataset with **only changed appdata.json** → same Content/Section/Unit IDs, no duplicate collections/history; only reviewed settings considered.
3. Same legacy `(type,id)` in **two distinct dataset scopes** → no accidental cross-profile merge; moving folder and explicitly reattaching same dataset → no duplicate mappings.
4. Legacy `history.db` with provable single position → correct canonical `unitId` through UC-005b; unknown index base, conflicting `readEpisode`, changed page order or missing media → review/unresolved, *no* new active session.
5. Existing v2 active ReadingSession newer than old history → never auto-rewind; imported timestamp remains historical evidence, not forged `updated_at`.
6. `history.db.image_favorites` and `local_favorite.db` favorite comics stay distinct; first staged if unsupported, second becomes UserCollection membership only with mapped Content.
7. Malicious dynamic folder table name / quote / internal SQLite table / malformed column signature → safe rejection or escaped identifier query, no SQL execution beyond reviewed templates.
8. Active WAL or missing sidecar, locked SQLite, corrupt input, malformed JSON, oversized nested JSON → stable typed failure/skip without writing source; no partial source-file copy.
9. User picks old Unified Store `venera.db`, renamed Unified Store named `local.db`, or v2 destination through symlink → reject by file signature/identity; strict input allowlist unchanged.
10. Unsafe media path, symlink traversal, path reassignment, missing directory or outside-root file → rejected/unresolved without filesystem escape.
11. Crash after staging, after promotion before DB commit, during commit, after commit before receipt → deterministic resume/GC, no orphan-readable state, no duplicate canonical IDs.
12. Concurrent import retry and user re-run for same dataset → serialized mapping updates and uniqueness guard; no double-create.
13. `appdata.json` and `implicitData.json` contain auth strings, JS code, URL injection, unknown keys → never imported/executed/logged; approved typed preference only.
14. No M2 tag mapper yet → tags retained only as bounded evidence, never persisted to nonexistent canonical tag tables.
15. Source-only favorites/history and unavailable provider → unresolved without SourceLink fabrication, account prompt, network call or plugin execution.
16. Input absent/unknown schema/deferred phase/cancelled → precise per-file + category counts; user can inspect local receipt and purge staging independently.
17. Injected SVG/HTML titles, folder names and tag translations → rendered as escaped text; no reader/UI script execution.

## 10. Review blocker resolution ledger

| Review finding | Resolution in this proposal | Status |
|---|---|---|
| P0: Snapshot hash wrongly used as record identity | `3` Batch vs Dataset vs Record identities + mapping revisions | Contract specified |
| P0: SQLite/files claimed atomic | `6` journal, staged promote, DB visibility commit, crash table | Contract specified |
| P0: History indices ambiguously assigned | `5` evidence-ranked categorical mapping; UC-005b only; no guess | Contract specified |
| P1: WAL vs five-file scope | `1–2` SQLite sidecars solely for snapshot, not metadata inputs | Contract specified |
| P1: No unresolved staging model | `3` typed staging schema, lifecycle, retention, uniqueness | Contract specified |
| P1: Image Favorites conflated with collection items | `4.2–4.3` distinct destination and deferred model | Contract specified |
| P2: Malformed escaped Markdown + M1 tags | Proper Markdown code spans; tags staged until M2 (§4, §8) | Contract specified |

**Research trail:** inspected old Venera file readers in `lib/legacy/foundation/db/local_comics_store.dart`, `history_store.dart`, `favorites_store.dart` and `lib/legacy/foundation/appdata.dart`. Their source code informs fixtures only; the Unified Store and its modules are not allowed importer inputs or code dependencies.

**Canonical adoption status (Draft PR #6 only):** entity, DDL, use case, port, feature, diagnostics, plugin-boundary, milestone and index updates have been committed to 01/02/03/04/05/07/09/11/SUMMARY. This file is supporting rationale, not a second executable schema or repository authority. **Unmerged documentation is not implemented functionality**; no existing runtime or user data was modified.
