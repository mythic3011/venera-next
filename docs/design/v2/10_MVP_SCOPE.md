# Venera MVP Scope

> Companion to the v2 design set (00–09). Defines the smallest shippable product slice,
> what is deliberately **out**, and which review findings gate the build.
> Milestone sequencing lives in `11_MILESTONES.md`.

---

> **Greenfield reset (2026-10-09):** the current legacy runtime is discarded; M1 is a new implementation against the canonical `contents/content_sections/content_units` model and fresh SQLite schema. Historical `Implemented (Core+DB)` annotations below do not mean code is retained or reused. There is no old `comics/chapters/pages` migration, compatibility adapter or legacy source runtime requirement in M1. A separate one-time importer (proposal `17_LEGACY_DISTRIBUTED_IMPORT.md`) accepts only `local.db`, `history.db`, `local_favorite.db`, `appdata.json` and `implicitData.json` from old Venera; it rejects old Unified Store `venera.db`. This separate feature does not change M1 greenfield scope.

## 1. MVP Statement

**A standalone desktop app where a user imports local comic files, reads them, and always resumes exactly where they left off.**

One sentence, three promises: *import works*, *reading works*, *position never lies*. Everything in the MVP exists to keep those three promises; everything that doesn't is out.

Deployment target: **Standalone only** (Electron shell, local SQLite, no auth, no network account features). This is the topology 00_OVERVIEW already defines as minimal, and it exercises the full architecture spine (domain → use cases → ports → SQLite adapter → shell) without any hosted-only machinery.

## 2. Why this cut

- **It proves the load-bearing design decisions early.** The riskiest v2 contracts are the reader-position model (lifecycle rows + partial unique active index), the unit-order completeness rule, the storage object/placement split, and the import preflight/repair path. All four are fully exercised by local import + read + resume. If these survive contact with reality, the rest of the design stands on solid ground.
- **It avoids every non-MVP subsystem.** MVP is local-only, so it does not exercise remote ContentUnit materialization (N8), the plugin install pipeline (08), auth/HMAC key rotation (N17), or sync/backup identity matching (N13). Those contracts are written, but their implementation belongs to later milestones.
- **Importers run as bundled official plugins, but the install pipeline stays out.** 05 already provides the escape hatch: official plugins are "bundled with app", `isolation: shared`. MVP loads bundled importers directly from the app package — no repository client, no download, no signature verification, no PackageStore. The plugin *runtime message protocol* is exercised (so the SDK contract gets validated), the plugin *acquisition* pipeline is not.

## 3. In Scope

### 3.1 Packages (from 04)

| Layer | Packages |
|---|---|
| Leaf | `@venera/events`, `@venera/content-profiles`, `@venera/i18n` (labels only, OpenCC lazy), `@venera/permissions` (constants only — no enforcement in standalone) |
| Core | `@venera/schema`, `@venera/sdk` (importer surface only) |
| Pieces | piece-schema, piece-events, piece-database, piece-content, piece-reader, piece-storage (local_app_data only), piece-plugin-runtime (bundled-load path only) |
| Adapters | adapter-sqlite, adapter-electron, adapter-test, adapter-memory |

Explicitly deferred packages: `@venera/tags` (taxonomy ships, mapping UX doesn't), `@venera/api`, `@venera/client`, all auth/rate-limit/audit/telemetry/ws/admin/setup pieces, all non-SQLite DB adapters.

### 3.2 Schema subset (from 02)

Tables created in the MVP migration baseline:

- `contents`, `content_metadata`, `content_titles`
- `content_sections`, `content_units`, `content_unit_orders`, `content_unit_order_items`
- `source_platforms` (seeded: `local`), `source_links`, `section_source_links` (written by import provenance; no remote flows)
- `reading_sessions`
- `storage_backends` (seeded: one `local_app_data` row), `storage_objects`, `storage_placements`
- `operation_idempotency`
- `import_jobs`
- `diagnostics_events`

Not created yet (added by later milestone migrations — pre-stable schema may still be reset, per 00 §4): auth tables, audit tables, telemetry tables, relationship/fingerprint/vector tables, collections, tags, download/notification/update/stats/search/filter tables, plugin repository/artifact tables.

> Note: `user_collections` is *close* to MVP-cheap but is still out — see §4. If M2 lands fast this is the first thing back in.

### 3.3 Use cases (from 03)

| UC | Contract status | MVP role |
|---|---|---|
| UC-001 Create Content | Implemented (Core+DB) | via import; direct create exposed in dev tools only |
| UC-003 Update Content Metadata | Implemented | rename title, set cover |
| UC-004 Remove Content | Planned Canonical | library hide |
| UC-004b Permanently Delete Content | Planned Canonical | with confirm; exercises transaction semantics #4 |
| UC-005 Open Reader (+ ResolveReaderTarget) | Target | the core loop |
| UC-005b Update Reader Position | Target | the core loop |
| UC-006 Get Reader Position | Target | resume |
| UC-007 Clear Reader Position | Planned Canonical | abandon-in-place |
| UC-011 Create ContentSections from Import | Deferred/Legacy → promoted for MVP | via ImportJob pipeline, container-kind validation ON |
| UC-014 List All Contents | Deferred/Legacy → promoted for MVP | library browse, title sort |
| ImportJob orchestration (05) | Target | archive + directory importers |

Search (UC-013/UC-SEARCH-*) is **not** in MVP; library browse + title-substring filter over `contents.normalized_title` (a plain LIKE on the existing index) covers the need at MVP library sizes.

### 3.4 Bundled importers (from 05)

- `@venera/importer-archive` — CBZ/ZIP (CB7/CBR follow-up; format breadth is not an MVP promise)
- `@venera/importer-directory` — directory of images

Both run through `defineImporter` + `ImporterContext` for real: preflight → decision (`duplicate`: skip/replace/keep_both) → allocateStorageObject → copyFile → registerContent. The repair path (`repair_existing` keeps contentId) ships, because it is an invariant (SUMMARY #34), not a feature.

### 3.5 Content types

`comic` only at MVP. The ContentProfile mechanism ships (it's a lookup table, zero marginal cost), but only the comic profile is reachable through importers. `webtoon` (SCROLL mode) is the first post-MVP type since it shares the image pipeline.

## 4. Out of Scope (and why)

| Cut | Reason | Returns in |
|---|---|---|
| Remote providers / online reading | Depends on the N8 unit materialization contract; outside the local-only MVP promise | M3 |
| Plugin install pipeline (repo/verify/PackageStore, 08) | Bundled-only sidesteps it; biggest security surface deserves its own milestone | M3 |
| Collections | Real feature, zero coupling to the three MVP promises | M2 (first in line) |
| Tags UX / canonical mapping | Taxonomy constants ship; mapping/browse UX is separable | M2 |
| Search (FTS/vector) | LIKE-filter suffices at MVP library scale | M2 (FTS), M6 (vector) |
| Hosted mode, auth, API, admin/setup | Different topology; N17 HMAC key lifecycle ships with hosted auth | M4 |
| Downloads / update checks / notifications | Remote-only concerns | M3/M5 |
| Backup/restore | N13 identity ladder belongs with backup/restore implementation | M5 |
| Reading stats / streaks | Analytics is not a core import/read/resume promise | M5 |
| Recommendation / fingerprints / vectors | Whole subsystem; needs library data to exist first | M6 |
| Parental controls | Uses N5 fail-closed content rating contract; not part of MVP promise | M5 |
| Audit hash chain, OTel export | Standalone MVP uses diagnostics_events only | M4/M7 |
| i18n beyond zh-HK/en labels | Mechanism ships, translation breadth later | ongoing |

## 5. Design Gates (findings that block MVP code)

From `REVIEW_FINDINGS_2026-07-02.md` — these contracts are now written into the design set. The gates below are implementation/test gates: the corresponding code must satisfy the corrected contract before that slice is considered done.

| Finding | Why it gates MVP | Gate point |
|---|---|---|
| N1 event name (`content.updated`) | MVP emits this event | before `@venera/events` |
| N12 ImportJob pending→cancelled | MVP import queue needs cancel | before ImportJob orchestration |
| N14 importer example fixes | Bundled importers are written from these examples | before importer implementation |
| N16 annotation offsets | Only if annotations table is created early — it isn't; ignore for MVP | n/a |
| Prior #4 consolidation: `import_jobs` DDL | `import_jobs` moves from 05 into 02 when the MVP migration baseline is written | at migration baseline |

Everything else in the findings list gates a *later* milestone, not MVP (mapped in `11_MILESTONES.md`).

## 6. MVP Acceptance Criteria

Functional:

1. Import a 200-file CBZ → content appears with sections/units in canonical order; cover set from first unit; re-importing the same file triggers the duplicate decision; choosing *replace* preserves the contentId (repair path) and existing reading position remains valid.
2. Open reader with no saved session → first canonical section, unit 0 (`first_canonical_section` resolution reason).
3. Read to page N, close app, reopen, open content → resumes at page N (`saved_session`), and `reading_sessions` contains exactly one `active` row for that content.
4. Clear position → row becomes `abandoned` in place; next open starts at first canonical section; no rows were hard-deleted.
5. Permanently delete a content mid-read → transaction completes; no FK error from `reading_sessions.unit_id` (deferred FK contract holds); no orphan rows in any MVP table.
6. Kill the app mid-import → restart shows the ImportJob as `failed`/resumable, library contains no half-registered content (import transactionality), and orphaned storage objects are detectable.

Non-functional:

7. Open reader (cold, 500-unit section) `<` 300 ms on the reference dev machine; position write `<` 20 ms (both are single-index lookups by design — if they miss by 10×, the schema has a problem worth finding now).
8. Every MVP invariant has a test: one active session per content, unit-order completeness → VALIDATION_ERROR, unitIndex uniqueness, storage object without placement → STORAGE_OBJECT_UNAVAILABLE, idempotent create replay.
9. Zero imports of Kysely/SQLite/Electron inside `src/domain`, `src/application`, `src/ports` — enforced by a lint rule, not review vigilance (00 §4 hard rule).

## 7. MVP Non-Goals Restated

The MVP is not trying to be: multi-content-type, multi-device, online, social, or extensible-by-third-parties. It is trying to prove that the v2 core — identity, structure, ordering, position, storage — is correct, pleasant to build on, and honest under crash and re-import. That proof is what every later milestone stands on.
