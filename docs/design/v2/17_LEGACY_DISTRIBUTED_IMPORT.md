# v2 One-Time Legacy Venera Distributed-Data Import

> **Status: scoped design proposal, 2026-10-09.** The current Venera runtime is discarded. This is a **separate, user-initiated, one-way importer** for **only five specified legacy Venera files**. It is not an in-place database schema migration, not a legacy code compatibility adapter, and not an implemented feature. See [10_MVP_SCOPE.md](10_MVP_SCOPE.md), [11_MILESTONES.md](11_MILESTONES.md), and [16_ACCOUNT_PASSKEY_ADOPTION_CONTRACT.md](16_ACCOUNT_PASSKEY_ADOPTION_CONTRACT.md).

## 1. Exact scope and hard exclusions

**Allowed input files, by exact basename:**

| Input | Known legacy source evidence | Data eligible for preview and import |
|---|---|---|
| \`local.db\` | \`lib/legacy/foundation/db/local_comics_store.dart\`; \`comics\` table | Local works, chapter descriptions, referenced local file paths, cover hints, tags, download-local status; actual page bytes only from explicitly selected/authorized local content roots |
| \`history.db\` | \`lib/legacy/foundation/db/history_store.dart\`; \`history\` and \`image_favorites\` | Reading history, legacy episode/page indexes, timestamps, image favorites where supported |
| \`local_favorite.db\` | \`lib/legacy/foundation/db/favorites_store.dart\`; per-folder tables | Favorite folder labels/order, members and source-type evidence; folder table names are **data**, never interpolated into untrusted SQL |
| \`appdata.json\` | \`lib/legacy/foundation/appdata.dart\` | Allowlisted non-sensitive reader and display preferences; selected legacy source hints for user review |
| \`implicitData.json\` | \`lib/legacy/foundation/appdata.dart\` | Only reviewed non-secret, non-executable fields with an explicit mapping; otherwise preserve a count of skipped entries, not payloads |

**Explicitly unsupported:** Unified Store \`venera.db\`, its \`source_platforms\`, \`reader_tabs\`, \`history_events\`, \`favorite_folders\`, \`app_settings\` and every other Unified Store table; \`syncdata.json\`; any other legacy SQLite/JSON file; direct JS plugin binaries; arbitrary script archives; raw stored passwords, cookies, access tokens, API keys and authenticated browser profiles.

The folder-selection UI and parser registry MUST enforce an exact five-file input allowlist. Do not automatically treat a filename \`venera.db\` as legacy import input merely because new v2 canonical DB is also named \`venera.db\`. **New v2 data/venera.db is the destination and must never be opened as a legacy input.**

A non-present optional input yields \`SKIPPED_MISSING_INPUT\`, not an error. The importer can operate on a subset; the preview must show which files were supplied and which were not. The user can select an explicit legacy data folder or individual allowed files; never perform an unbounded filesystem scan.

**Referenced local media:** \`local.db\` may point to image directories outside these five files. The importer can offer a separate **user-approved asset-root access grant** to copy or reference those actual images, but this is not permission to import another legacy metadata store. No arbitrary path traversal, symlink escape, or remote file fetch from untrusted stored paths.

## 2. Architecture: import tool only, no runtime bridge

~~~text
Trusted "Import from old Venera" UI (explicit user intent)
   -> Allowed-file picker (5 names; destination excluded)
   -> Snapshotter (SQLite consistent read-only backup; bounded JSON copy)
   -> Untrusted-input parser (isolated; strict schemas/quotas)
   -> LegacySourceResolver (old source key/type -> reviewed identity proposal)
   -> Normalizer (legacy rows -> ProposedContent/Section/Unit/Collection/History)
   -> IdentityReconciler + ConflictAnalyzer (NO title-only auto-match)
   -> DryRunReport + user-controlled decisions
   -> V2 use case / repository import transaction writer
   -> PostCommitVerifier + receipt/rollback status
~~~

No imports from \`lib/legacy\` into the new runtime; old Dart files are **reference documentation for writing fresh isolated readers**. Old SQLite rows are untrusted data. Importer is a one-shot trusted application service, not an executable provider plugin and not an API exposed to third-party JS plugins.

**Consistent snapshot:** prompt user to close old Venera, use a read-only SQLite connection and SQLite backup API or another database-consistent snapshot mechanism; do not naïvely copy just \`*.db\` while a live WAL file may contain committed transactions. Backup target in a private temporary directory; verify \`PRAGMA quick_check\`, \`foreign_key_check\` when applicable, and schema compatibility before parsing. On unknown schema variant, do not run migrations on source; fail that file with structured unsupported-version result.

Verify file signatures, sizes, SQLite \`sqlite_master\` table/column sets and JSON top-level shapes. Hard-cap per-file size, row count, JSON recursion/nesting, text lengths, attached content bytes, page count and total run time. Never execute source-supplied SQL, JS, custom functions, triggers or extensions. Use read-only \`query_only\` mode where feasible and disable any extension loading/unsafe SQL. Since \`local_favorite.db\` has dynamic folder tables, discover and validate identifiers, quote as identifiers safely in a reviewed adapter and require expected columns.

## 3. Deterministic data mapping and uncertainty

### 3.1 Local comics

- Parse \`local.db.comics(id, comic_type, title, subtitle, tags, directory, chapters, cover, downloadedChapters, created_at)\`; exact schema may vary: probe and validate instead of assuming columns.
- Create new v2 \`ContentId\` UUID, \`ContentSectionId\` UUID and \`ContentUnitId\` UUID; assign new stable unit order, StorageObject/Placement only for verified accessible media bytes. Preserve legacy identity **as importer mapping evidence only**, never reuse \`comic_type:id\` or filename as canonical ID.
- File and chapter ordering comes from validated legacy chapter map and actual readable filenames, with collision checks. Preserve original order as evidence. A title match is only a review suggestion and must not silently merge distinct comics.
- If the referenced directory is missing, allow **metadata-only unresolved** import only as an explicit choice and mark readable availability accurately; do not produce reader entries pointing to nonexistent images or a fabricated cover.
- Each import copies eligible user-selected files into owned storage or adopts an explicitly authorized managed location through a verified storage contract. Do not import arbitrary absolute paths into canonical metadata as automatically readable authority.

### 3.2 Favorites and history

- \`local_favorite.db\` is an older dynamic per-folder SQLite shape; map known fields \`id, name, author, type, tags, cover_path, time, translated_tags, display_order\` after inspecting each folder table.
- Map folders to v2 \`UserCollection\` and memberships, preserving intended order. Imported source favorites without an installed/verified source remain **unresolved references** awaiting later account/source matching; don't fabricate working SourceLinks.
- \`history.db.history\` includes \`id, title, subtitle, cover, time, type, ep, page, readEpisode, max_page, chapter_group\`. Treat \`ep\`, \`page\`, \`type\`, \`chapter_group\` as legacy evidence; **never** assume the integer equals the new \`ContentSection\`/\`ContentUnit\` ID or active order.
- Resolve history position only when work identity and chapter/page can be matched unambiguously against imported units (and, where useful, media identity). Then create/update \`ReadingSession\` according to canonical current position policy.
- Ambiguous, source-only, missing-media or changed-order positions stay in a **staging review record**; show original chapter/page index and reason. Never silently point to another page or create fake ContentUnits to make progress look valid.
- Preserve useful history timestamps as historical evidence where supported. A history log is not itself an active ReadingSession. Multiple legacy records conflicting for the same work require an explicit deterministic policy and review.

### 3.3 Preferences and implicit data

- Parse \`appdata.json\` only through a per-key **allowlist** of non-sensitive preferences (e.g., reader display/scroll/gestures where semantics are verified). Unknown/obsolete settings are skipped, not injected into runtime configuration.
- Parse \`implicitData.json\` only with a reviewed schema and key map; default is **skip unknown fields**. Never import raw JWT, bearer, cookie, password, request headers, fingerprinting IDs, session/account state, dynamic script bodies or unrestricted URLs.
- Do not auto-install old website source scripts or preserve legacy signed-in state. After the later v2 Provider/AccountProfile feature exists, the trusted UI may offer source account re-connection by **new login**, with a fresh vault record.

## 4. Import state, idempotency and safety

- UX: \`Select\` → \`Snapshot\` → \`Inspect\` → \`Preview\` → \`Resolve conflicts\` → \`Commit\` → \`Verify\` → \`Receipt\`. Preview is read-only and gives per-file eligible/importable/skipped/ambiguous counts; approval is explicit.
- Preserve original files and source media. No delete, overwrite, \`ALTER TABLE\`, VACUUM or cleanup of legacy source during import. Source snapshot is private, temporary and removed after completion/cancellation according to retention policy.
- Compute stable **import input fingerprint** from full snapshot hashes + file-role manifests (order-independent), not from content title or path alone. Persist a one-time import receipt and mapping table for source-record IDs → fresh v2 IDs, keyed by import batch and input scope. Mapping key must include file kind and (where needed) source type, not bare id.
- On retry after crash, do not duplicate imported \`Content\`, collections or history. Use application-level idempotency keys + DB uniqueness where applicable; stage and atomically commit each **complete** content subtree (Content + Section + all resolved Units + active order + source evidence) and verified StorageObject placements.
- A partially accessible legacy folder must not cause a half-valid active unit order. Missing media may be separately staged and reported. Crash/rollback cleans orphaned temporary blobs; durable committed records are never silently re-imported or overwritten.
- Conflict policy for existing v2 library: \`skip\`, \`keep_both\`, \`merge_after_review\`, or \`repair_verified_same_asset\`, subject to documented v2 invariants. No title-only automatic merge, no blind \`INSERT OR REPLACE\`.
- Collect privacy-preserving diagnostics (file role, count, schema variant, error code, fingerprints and timing) without logging full titles, paths, old favorites, secrets or raw JSON/SQL.
- Default local-only processing; no uploads to Hosted, cloud OCR or external catalog lookup during migration. Any future assisted source reconciliation must require explicit user action and obey Source/Network/Auth Broker security.

## 5. Availability and milestone policy

- **Not part of M1 core import/reader runtime:** keep M1 greenfield local CBZ/folder import, read, resume. The legacy-data importer is a **separate bundled one-time migration tool** that calls the new v2 domain use cases, not the M1 importer plugin SDK and not legacy runtime.
- Proposed rollout: L0 adapter + fixture/schema audit; L1 local.db media + history reconciliation after fresh v2 Reader is usable; L2 favorite folders after M2 UserCollection; L3 source-only favorites/history unresolved staging and review once M3 source identity and account model exist.
- A single user-facing import operation can run whenever all selected category handlers are ready, or import safe available categories and preserve an explicit pending-review receipt. **Never claim complete import when requested categories are deferred.** If full five-file import is required, gate the full wizard until L1/L2/L3 have shipped.
- Legacy schema support is limited to the five files and inspected shapes; no support for the Unified Store even as a fallback. Future format additions require a new explicit user scope decision, never automatic autodetection from other databases.

## 6. Acceptance suite (new isolated fixtures, no legacy runtime execution)

1. \`local.db\` with 2 comics, ordered chapters and validated images → fresh Content/Section/Unit IDs and complete active unit order; no legacy ID leak.
2. \`history.db\` positions matched against verified local media → exact Unit resume; ambiguous/missing sources → unresolved report, no misleading session.
3. \`local_favorite.db\` dynamic table names, quotes/unicode/reserved names and malicious identifiers → safe discovery/identifier quoting, no SQL injection.
4. \`appdata.json\` reader settings preserved only for allowlisted keys; unknown, malformed, executable/sensitive values skipped.
5. \`implicitData.json\` contains old cookies/tokens/scripts → no secret/plugin import, log redacted.
6. All 5 absent / one absent / stale file / malformed DB / malformed JSON / WAL-active snapshot → transparent typed error/skip and intact original data.
7. Mix selected input folder containing \`venera.db\` or new destination \`data/venera.db\` → never open Unified Store as source.
8. Duplicate run and crash after partial commit → idempotent receipt, no duplicate Content/Order/Collection, consistent storage.
9. Missing local directory, symlink escape, relative traversal, oversized decompression/JSON → reject or staged unresolved, never outside explicit media grant.
10. Source-only favorite, unknown numeric source type and missing plugin → reviewed unresolved reference; no auto-executed legacy JS and no source alias guess.
11. Imported source data never opens a network request, login dialog or third-party plugin operation without new trusted user intent.
12. Report distinguishes imported/unchanged/unsupported/missing/ambiguous per category and input file; user can cancel before commit.

## 7. Research trail and adoption targets

Legacy shape evidence comes from:
- \`lib/legacy/foundation/db/local_comics_store.dart\` (legacy \`comics\` table)
- \`lib/legacy/foundation/db/history_store.dart\` (legacy \`history\`, \`image_favorites\`)
- \`lib/legacy/foundation/db/favorites_store.dart\` (per-folder dynamic tables)
- \`lib/legacy/foundation/appdata.dart\` (legacy JSON settings and implicit data)

Files under \`lib/legacy/foundation/db/unified_comics_store\` are **out of scope** and must **not** be an importer code dependency or accepted input shape.

When adopted, update \`03_USE_CASES.md\` with an explicit one-time import flow, \`04_PACKAGES_AND_PIECES.md\` with independent port/service, \`02_DATABASE_SCHEMA.md\` with import receipts and staging evidence, \`07_FEATURES.md\` for unresolved reconciliation UI, \`11_MILESTONES.md\` with L-series delivery gates, \`SUMMARY.md\` and \`docs/project-direction.md\` for the strict five-file scope. None of those should add an old-runtime read dependency.
