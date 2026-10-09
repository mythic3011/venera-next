# Venera Design v2 — Canonical Index

**Status**: Active canonical index. Supersedes both the archived v1 docs (`docs/design/archive/v1/`) and the archived `claude-version/` draft. Where v2 conflicts with either archive, v2 wins; the Decision Log below records every deliberate divergence.

> Agent instruction: read files in order before implementing. Do not skip files.

---

## File Map

| File | Contents |
|---|---|
| `00_OVERVIEW.md` | Architecture vision, layers, deployment topologies, persistence strategy & adapter boundary |
| `01_ENTITIES.md` | Core domain entities, recommendation graph/signal entities, full invariants + validation rules (authority file) |
| `02_DATABASE_SCHEMA.md` | Logical schema, SQLite reference DDL, FK semantics, transaction semantics, legacy guardrails |
| `03_USE_CASES.md` | Core use cases: content CRUD, source links, reader (ResolveReaderTarget policy), collections, idempotency flows |
| `04_PACKAGES_AND_PIECES.md` | Package catalogue, Piece/DI system, route & middleware patterns, networking policies |
| `05_PLUGIN_SYSTEM.md` | All plugin types, manifest, ImportJob contract, SDK, PluginProxy security, worker lifecycle |
| `06_SECURITY_AUTH_RECOMMENDATION.md` | Threat model, privacy tiers, audit hash chain, auth, recommendation engine, OTel log format, implementation priority |
| `07_FEATURES.md` | Download manager, notifications, content update, reading stats, search, backup/sync, content filtering, CoreRepositories |
| `08_SOURCE_PACKAGE_LIFECYCLE.md` | Source package install commit order, lease timers, trust tiers, PackageStore contract (authority over 05's summary) |
| `09_OBSERVABILITY.md` | Diagnostics events contract (bounded evidence, best-effort writes, schema evolution policy) |
| `10_MVP_SCOPE.md` / `11_MILESTONES.md` | Greenfield release scope and phase gates; legacy-import L0–L3 is separate |
| `17_LEGACY_DISTRIBUTED_IMPORT.md` | Companion rationale, exact five-file formats, mapping examples, threat cases and acceptance fixtures. **Normative entity/schema/use-case authority remains in 01/02/03, not 17** |

> **2026-10-09 greenfield ruling:** Current `runtime/core` and other legacy execution code will be retired, not refactored. Canonical v2 documents define the **new implementation target**; historical “Implemented (Core+DB)” status lines refer to code being discarded and must **not** be used as evidence that fresh v2 runtime components already exist. No migration of legacy Comic/Chapter/Page database schemas is required. One-time old-Venera import is strictly scoped to `local.db`, `history.db`, `local_favorite.db`, `appdata.json`, and `implicitData.json`, and explicitly excludes Unified Store `venera.db`. See `17_LEGACY_DISTRIBUTED_IMPORT.md`; the one-time import **domain, DDL, use cases, adapter boundary, features and diagnostics are now integrated into 01/02/03/04/05/07/09** on this draft branch. This is documentation adoption, **not** runtime implementation, not legacy code reuse and not a compatibility layer. Account/source-scope and passkey designs (12–16) remain proposals in Draft PR #6; legacy import 17 is supporting design evidence after canonical document integration, all still unmerged.

Implementation status vocabulary (carried from v1, applies per use case / per table):
`Implemented (Core+DB)` | `Target` | `Planned Canonical` | `Deferred/Legacy`.

---

## Naming Conventions (v2)

```
v1 name (do not use)    →   v2 name
─────────────────────────────────────────────
Comic                   →   Content
ComicId / comic_id      →   ContentId / content_id
ComicMetadata           →   ContentMetadata
ComicTitle              →   ContentTitle
Chapter                 →   ContentSection
chapter_id              →   section_id
ChapterSourceLink       →   SectionSourceLink
Page                    →   ContentUnit
page_id / page_index    →   unit_id / unit_index
PageOrder / PageOrderItem → ContentUnitOrder / ContentUnitOrderItem
ReaderSession           →   ReadingSession (table: reading_sessions)
coverPageId             →   coverUnitId
page_image (objectKind) →   unit_image
is_active boolean       →   status enum
orderKey / pageCount    →   removed (orderType only; counts derived from items)
```

`sectionKind` keeps `chapter` as an enum VALUE for visual content (season | volume | chapter | episode | oneshot | group) and adds text kinds (section | entry | article | part). Renaming the entity does not rename the kind.

---

## Critical Invariants (merged, canonical)

```text
Identity & provenance
 1. Content owns canonical identity. normalizedTitle is a non-unique search signal,
    never identity. SourceLink/SectionSourceLink are provenance evidence only.
 2. (sourcePlatformId, remoteWorkId) unique; lifecycle is update-in-place; rejected/
    stale rows do not free the provider work ID.
 3. originHint is derived from active local/remote content-bearing source links and
    updated in the SAME transaction as source-link mutations. virtual platforms never
    contribute to originHint and never model user collections (UserCollection does).
 4. ContentTitle: at most one primary per content (DB partial unique); minimum-one
    enforced at app layer in the same transaction that maintains the
    content_metadata.title denormalized cache. Logical title uniqueness treats
    NULL locale/source platform as value-bearing buckets and must be enforced by
    backend-specific index or a named transaction guard.
 5. contentType is immutable; it selects ContentProfile, not schema.

Structure & ordering
 6. sectionNumber is an optional DecimalString ordering hint — never identity,
    never Float arithmetic, never lexicographic comparison.
 7. Section hierarchy: acyclic, no self-parent, max depth 8; parent deletion must be
    explicit (delete_subtree | reparent_children | reject_if_children) — never
    silent root promotion (FK is NO ACTION DEFERRABLE, not SET NULL).
 8. Container kinds (season/volume/group) must not own readable units directly;
    import/use-case flows reject plans that assign units directly to containers.
 9. unitIndex: 0-based, unique per section, gaps allowed. Display order authority is
    the active ContentUnitOrder + items; one orderType discriminator, lifecycle
    status enum, no orderKey/isActive/count caches.
10. An active-but-incomplete unit order is a VALIDATION_ERROR — no silent fallback.
    Synthetic source order (unitIndex ASC) applies only when no active order exists.

Reading sessions
11. Position authority is unitId; sectionId/unitIndex are derived via join, never stored.
12. Lifecycle rows: at most ONE active session per content (partial unique index);
    non-active rows are historical evidence; only active rows are resume candidates.
13. Clear Position marks the active row abandoned in place — no hard delete.
14. unit_id FK must not be immediate RESTRICT; Content purge must not depend on
    cascade ordering. sourceLinkId on a session is read-context evidence only;
    stale source context never invalidates a valid saved unit.
15. Core persistence is last-write-wins, single runtime. Multi-device sync requires
    an explicit conflict contract before version/device columns become authority.

Storage
16. StorageObject row existence ≠ byte availability; a readable StoragePlacement is
    required, else STORAGE_OBJECT_UNAVAILABLE / explicit placeholder state.
17. At most one authority placement per object (DB partial unique index).
18. StorageBackend kinds are local_app_data/webdav/plugin/future; plugin
    backends require `pluginKey`; config is schema-versioned, fail-closed on
    unsupported versions; secrets only via secretRef to an OS/deployment
    credential store.
19. Raw filesystem paths are never canonical storage identity.

Idempotency
20. OperationIdempotencyRecord is composite-keyed (operationName, idempotencyKey)
    with canonical input hash; full replay/conflict/lease/retry-TTL contract in
    02_DATABASE_SCHEMA.md. Same key + different input = IDEMPOTENCY_CONFLICT.

Source packages & plugins
21. Hard commit order: authentic + verified artifact → PackageStore commit →
    source_platform mutation. No step may run early; failed mutation → rollback or
    orphan; lease/TTL timers in 08.
22. Manifest trust tier ∈ {official, community, custom}; install-time verification
    tier adds unverified. unverified is never one-button installable or executable.
23. Verification evidence (verificationTier, publisherKeyFingerprint,
    signatureDigest) is persisted; signatureValid is never a stored mutable boolean.
24. Plugin permissions: declared subset of Roles.PLUGIN, validated at install.
25. PackageStore owns artifact lifecycle state; `installed_plugins.state` owns
    runtime state only. Reader-mode IDs are `(pluginKey, modeId)`, never bare
    plugin-declared mode strings.
26. Plugin DB access only via controlled ports; plugin outbound fetch only via
    PluginProxy (scheme + domain allowlist + public-address check + manual-redirect
    re-validation + rate limits); importer file access via realpath sandbox.
27. Trust is cryptographic (signed index + signed entry + archive SHA-256);
    mirrors are untrusted byte relays.

Security & privacy
28. Actor resolution is server-side; never trust client-supplied actor fields.
29. Audit events are append-only, hash-chained, externally checkpointed; the
    repository port exposes no update/delete.
30. Auth secrets: random tokens/API keys stored as selector + HMAC-SHA256(verifier)
    + key_id; argon2id only for low-entropy secrets (passwords, PINs). HMAC keys
    rotate by key_id and live only in OS/deployment secret storage.
31. Privacy is schema-level: TIER 0 fields cannot exist in log schemas; TIER 1
    one-way hashed; logs use the OTel model with pre-approved attribute keys only.
32. File type detection by magic number, never extension alone.

Observability
33. Diagnostics events are schema-versioned, best-effort evidence writes — they must
    never fail or roll back the primary business use case, and never mutate state.
    Additive payload fields may stay on the same major schema; breaking payload
    changes require a major version bump and reader compatibility path.

Tags & import
34. Tags are taxonomy/mapping-based (canonical_tags + source_tags + user layers),
    never loose genre strings. Tag keys are slugified (lowercase, spaces →
    underscores) with display labels stored separately per locale. zh-HK/zh-TW
    labels may be auto-generated via OpenCC and marked as "auto_opencc".
35. Import repair path preserves the existing contentId (keeps sessions + tags).
    Adapters send intent; application use cases own workflow.
36. Remote provider units materialize into canonical ContentUnit rows before
    online reading or download. Provider URLs/order are provenance evidence, not
    identity; existing units referenced by sessions are never renumbered/deleted.
37. `userRating` is the 1..5 personal/library rating used by search and backup;
    `contentRating` is the separate ordered safety/filter scale.

One-time distributed-data import (separate from plugin import)
38. Only local.db, history.db, local_favorite.db, appdata.json and
    implicitData.json are eligible old-Venera metadata inputs. Legacy Unified
    Store venera.db is rejected by filename AND schema signature even if renamed.
    SQLite WAL/SHM sidecars are snapshot mechanics, not sixth input types.
39. ImportBatch (Deferred/Legacy) and plugin ImportJob are distinct from
    LegacyImportDataset/LegacyImportBatch/RecordMapping/Receipt/AssetJournal.
    Snapshot digest is batch evidence only; dataset-scoped record keys preserve
    fresh canonical IDs across reruns and changed preference snapshots.
40. SQLite transactions do not atomically cover file bytes. Journal + staged
    verification/promotion precede the full Content/Section/Unit/active-Order/
    Placement + mapping DB visibility commit; recovery/GC cannot touch user
    originals or referenced placements. Partial batches never show partial
    active unit orders.
41. Old ep/page/readEpisode/chapter_group are uncertain evidence, not UUIDs.
    Only a uniquely VERIFIED_UNIT can update position via UC-005b after
    checking existing active v2 session; ambiguous states remain reviewable.
42. Favorites in local_favorite.db map to UserCollections only with verified
    Content IDs (M2); history.db.image_favorites is a distinct deferred
    image-level category. Tags are evidence until M2, and source-only
    unresolved identity awaits explicit review after M3. No secret/JS import.
```

---

## Decision Log (v1 vs claude-version conflicts — resolved)

| # | Topic | claude-version draft said | v2 decision | Why |
|---|---|---|---|---|
| D1 | Naming | Content/Section/Unit rename | **Adopted** | Universal content platform; rename is mechanical |
| D2 | Scope | Plugin system, auth, audit, recommendation, features | **Adopted** (as Planned/Target status, not implemented authority) | Real product scope; status labels prevent fake "done" claims |
| D3 | ReadingSession | `UNIQUE(content_id)`, one row upserted | **Rejected** → lifecycle rows + partial unique on active (v1) | One-row model contradicts its own sessionState enum; Clear→abandoned and stats need lifecycle evidence; resume path stays simple via `WHERE active` |
| D4 | reading_sessions.unit_id FK | `ON DELETE RESTRICT` | **Rejected** → `NO ACTION DEFERRABLE INITIALLY DEFERRED` (v1) | Immediate RESTRICT makes Content purge depend on cascade ordering |
| D5 | parent_section_id FK | `ON DELETE SET NULL` | **Rejected** → `NO ACTION DEFERRABLE` + explicit delete modes (v1) | SET NULL silently promotes children to root |
| D6 | Primary title | "Exactly one primary, DB-enforced" | **Corrected** → at most one (DB) + minimum-one (app layer) | A partial unique index cannot enforce existence |
| D7 | content_titles logical uniqueness | dropped | **Restored** (v1) + SQLite expression unique index | Prevents duplicate title evidence per locale/platform; NULL buckets are value-bearing |
| D8 | Idempotency | "TODO: TTL cleanup" | **Restored** full lease/retry/claimOrReplay contract (v1) | Crash-liveness and replay semantics are core correctness, not a TODO |
| D9 | Manifest trustTier | included `unverified` | **Corrected** → manifest: official/community/custom; unverified is verification-result only (v1 rule) | Publisher intent vs install-time outcome are different facts |
| D10 | Artifact verification evidence | dropped fingerprint/signature fields | **Restored** publisher_key_fingerprint + signature_digest (v1) | Required audit evidence; signatureValid-as-boolean forbidden |
| D11 | Auth token storage | argon2 token_hash with UNIQUE lookup | **Redesigned** → selector + HMAC-SHA256(verifier); argon2id only for passwords/PINs | argon2 is salted ⇒ lookup-by-hash cannot work; slow-hashing high-entropy tokens is pure latency. (New fix — neither doc had this right) |
| D12 | ws_tickets | raw ticket as PK | **Changed** → store ticket_hash, atomic single-use consume | Raw bearer credential in DB violates invariant 29 |
| D13 | PluginProxy | allowlist on initial URL only; `path.resolve` sandbox | **Hardened** → scheme allowlist, public-address (SSRF/rebinding) check, manual-redirect re-validation, response size cap; realpath + path.sep sandbox | Redirects and symlinks bypass the draft's checks. (New fix) |
| D14 | ImportBatch | replaced by plugin ImportJob | **Adopted** ImportJob entity contract as direction; ImportBatch kept as Deferred/Legacy reference | Keeps legacy use cases readable without dual authority |
| D15 | Reader resolution policy | absent | **Carried** ResolveReaderTarget fallback ladder + order-completeness validation + unit-availability rules (v1) | Core reader correctness contract |
| D16 | Diagnostics | only OTel logs + audit | **Carried** diagnostics_events as third surface with best-effort rule (v1) | Local/dev evidence ≠ logs ≠ audit; rule 32 |
| D17 | sectionKind enum | renamed away `chapter` value | **Merged** visual kinds keep `chapter`; text kinds added | Entity rename ≠ vocabulary rename |
| D18 | Favorites | not mentioned | **Kept Deferred/Legacy** (v1) | No favorites table in core pass; source favorite state stays on source_links evidence |
| D19 | Hosted sync columns (version/device_id) | presented as plain ALTER | **Gated** behind explicit multi-device conflict contract | Core contract is last-write-wins single-runtime |
| D20 | Adapter/persistence boundary docs | absent | **Carried, condensed** into 00_OVERVIEW §4 | Boundary + audit gates still bind future backend work |
| D21 | Old distributed user-data import vs discarded runtime | In-place legacy DB/runtime compatibility not desired | **Adopted on draft branch:** trusted one-time five-file importer, distinct from normal ImportJob, with canonical identity/DDL/use cases in 01–03 and L0–L3 phases | Preserve user library/progress safely without retaining vulnerable or obsolete execution model |

---

## Implementation Priority

The P0–P7 ladder in `06_SECURITY_AUTH_RECOMMENDATION.md` is the build order
(leaf packages → schema/ports/SQLite adapter → core use cases → API/auth →
plugins → recommendation → advanced → observability). Package dependency order is
in `04_PACKAGES_AND_PIECES.md`. Do not skip layers.

---

## Glossary

```
Content           Universal content item (comic, webtoon, novel, document, note, ...)
ContentSection    Structural node (chapter/episode for visual; section/entry for text)
ContentUnit       Atomic reading unit (image page, text block, PDF page)
SourceLink        Content ↔ remote work provenance edge (evidence, not identity)
SectionSourceLink Section ↔ remote section provenance edge (+ sourceOrder evidence)
ContentUnitOrder  Named unit-order profile; one active per section
ReadingSession    Reader position lifecycle row; unitId is position authority
StorageObject     Logical file metadata (existence ≠ bytes)
StoragePlacement  Physical placement on a backend; one authority placement per object
PackageStore      Durable authority for verified plugin artifacts (08)
TrustTier         Publisher intent: official | community | custom
VerificationTier  Install-time outcome: official | community | custom | unverified
PluginProxy       Mandatory chokepoint for all plugin outbound calls
AuditStream       Named append-only hash-chained audit sequence
PreflightDecision Import conflict decision (create_new / repair_existing / conflict_*)
LegacyImportDataset Old Venera installation/profile identity; not derived from snapshot hash
LegacyRecordMapping Persisted dataset-scoped per-record identity → canonical target mapping
LegacyAssetJournal Filesystem+SQLite crash recovery authority for one-time legacy import
LegacyImportReceipt Verified durable batch/category result; not a diagnostics event
```
