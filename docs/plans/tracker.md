# Venera Migration Timeline + Bug Tracker

## 0. Current Decision Snapshot

### Main decision

Local runtime should move to canonical-only authority.

Legacy local storage / JSON / old DB should not block:

- local import
- local list
- local detail
- local history
- local reader

Legacy local code can remain as:

- migration bridge
- best-effort mirror
- old-data compatibility

But it must not be the required authority for new runtime paths.

### Remote decision

Remote legacy source runtime remains for now.

Remote source system will be refactored later. Do not remove remote legacy source adapter yet.

### UI decision

Local and remote should share the same UI contract.

```text
Shared UI
-> Loader / Controller
-> Local service branch
-> Remote service branch
-> normalized ViewModel
-> ReaderOpenRequest only when user explicitly reads a chapter
```

Do not maintain separate local detail page and remote detail page unless the UI layout is genuinely different.

---

## 1. Timeline So Far

### Phase A - Source repository / Direct JS install lane

| Lane | Status | Notes |
| --- | --- | --- |
| M26.2-F1/F2/F3 | Closed | Source repository registry, diagnostics, redaction, typed URL failures |
| D1 | Closed | Direct JS validation-only; no install/write path |
| D2 | Closed | UI validate-only dialog; no install/write path |
| D3a | Closed | Skeleton contract tests only |
| D3c0 | Closed | Installed source authority inventory |
| D3c1 | Closed | Minimal write adapter implementation plan only |
| D3c2 | Closed | Guard command/tests; no write |
| D3c3 | Closed | Staged filesystem tests only |
| D3c4 | Closed | DirectJsStagedSourceWriter hardening |
| D3c5 | Closed | Parser/register handoff after staged commit |
| D3c full write path | Not started | Controller wiring, UI install enablement, provenance/hash still pending |

Important boundary:

```text
Source install UI must not expose fake install buttons while install path is disabled.
```

### Phase B - Local reader black-screen investigation

| Lane | Status | Findings |
| --- | --- | --- |
| R-local-1 | Closed | Local resume validation fixed; local pageOrderId == null no longer blocks resume |
| R-img-1 | Closed | Extracted image provider factory |
| R-img-2 | Closed | Image bytes loader extracted / diagnostics covered |
| R-img-3 | Closed | Extracted page load controller without moving UI state |
| R-img-4 | Closed | Added render terminal diagnostics |
| R-shell-1 | Closed | Active tab retention fixed; snapshot blind spot fixed |
| R-route-1 | Closed | Parent route/unmount diagnostics added |
| R-route-3 | Closed | Parent expected tab identity normalized to resolved sourceRef after loadData |

Key evidence:

```text
ReaderWithLoading.buildFrame expectedReaderTabId = local:local:1:_
Reader.open expectedReaderTabId = local:local:1:1:__imported__
activeReaderTabId = local:local:1:1:__imported__
```

Conclusion:

- page list loads
- provider created
- image bytes loaded
- decode succeeds

Remaining reader risk is no longer placeholder tab identity. It is now downstream route / entrypoint flow only.

### Phase C - Import canonical migration

| Lane | Status | Notes |
| --- | --- | --- |
| I-local-import-1 | Closed | CBZ import now routes through canonical storage; legacy local DB no longer required precondition |
| I-zip-1 | Closed | CBZ edge cases fixed: single cover page, folder collision, cache cleanup |

Important decision:

```text
canonical local storage unavailable -> fail closed
legacy local DB unavailable -> must not block canonical import
```

### Phase D - Hero / UI crash investigation

| Lane | Status | Notes |
| --- | --- | --- |
| UI-hero-1/2 | Closed | Cover Hero tags scoped by surface; duplicate cover7045321 crash fixed |

Important finding:

```text
Duplicate Hero tag can masquerade as reader lifecycle / black-screen bug
because Flutter route transition throws and then Reader gets disposed.
```

### Phase E - Comic detail maintenance

| Lane | Status | Notes |
| --- | --- | --- |
| Chapters lifecycle slice | Closed | TabController lifecycle fixed, grouped index mapping fixed, showAll reset narrowed |

---

## 2. Active Bug Tracker
### BUG-A1 - application data.json authority still mixed with DB authority

- **Status:** Closed for audit / owner / migration phase
- **Priority:** P2
- **Area:** AppData / settings authority

Problem:

Canonical DB exists, but `application data.json` is still created/used. Need to distinguish valid UI preferences from migrated data authority.

Do not delete blindly.

Fix direction:

- audit `appdata.json` keys
- classify:
  - UI preferences: keep in AppData JSON
  - local/history/favorites/source authority: move to DB or mark legacy bridge
  - migration-only keys: read-only / cleanup later
- add guard that local canonical domains do not require appdata JSON as authority

Audit-only scope for A-appdata-1:

- enumerate currently used `appdata.settings` and `appdata.implicitData` keys
- classify storage ownership without changing behavior
- record authority drift and unknown owners explicitly
- no migration
- no key deletion
- no default change unless owner is decided first

#### AppData / implicitData audit candidates

| Key | Storage | Current reader/writer | Classification | Owner / next action |
| --- | --- | --- | --- | --- |
| `reader_use_source_ref_resolver` | `appdata.settings` | `HistoryManager`, reader resume path, settings schema | feature flag / safe to stay in appdata | keep as typed setting; not authority by itself |
| `reader_use_resume_source_ref_snapshot` | `appdata.settings` | no runtime reader; retired migration flag residue | unknown / needs owner | owner decision recorded: retire as runtime flag; legacy resume compatibility now hangs off explicit `ReaderResumeService` fallback injection; no default, no `SettingKey`, no deletion in decision slices |
| `reading_resume_targets_v1` | `appdata.implicitData` | `ResumeTargetStore(appdata.implicitData)` | legacy bridge / resume snapshot cache | must not become canonical history authority; keep compatibility-only until owner is decided |
| `comicSourceListUrl` | `appdata.settings` | source init + repository seeding + legacy UI entrypoints | legacy source repository bridge | keep bridge semantics only; repository registry is canonical authority |
| `favoriteFolder` | `appdata.implicitData` | favorites page selection state | UI state / safe to stay in appdata | retain as view state; not favorites authority |
| `local_sort` | `appdata.implicitData` | local comics page sort selection | UI preference / safe to stay in appdata | retain as view preference |
| `local_favorites_read_filter` | `appdata.implicitData` | local favorites page filter selection | UI preference / safe to stay in appdata | retain as view preference |
| `local_favorites_update_page_num` | `appdata.implicitData` | local favorites page pagination/filter state | UI preference / safe to stay in appdata | retain as view preference |
| `localDirectoryBookmark` | `appdata.implicitData` | iOS local directory restore path | device integration / safe to stay in appdata | retain as device-local integration data |
| `followUpdatesFolder` | `appdata.settings` | follow-updates page + favorites manager | UI workflow preference / safe to stay in appdata | owner decision recorded: UI workflow state only; not source/update authority; keep in appdata unless future UI-state store migration happens |
| `webdavAutoSync` | `appdata.implicitData` | init/bootstrap + settings gateway | feature toggle / safe to stay in appdata | retain as device/runtime preference |
| `lastCheckUpdate` | `appdata.implicitData` | startup update check throttle | runtime cache / safe to stay in appdata | retain as cache-like throttle state |

Audit note:

```text
reader_use_resume_source_ref_snapshot is currently read by runtime but is not declared
in settings_schema.dart and has no dedicated default. The owner decision is to retire it
as a runtime flag, but the migration slice has not removed the runtime dependency yet.
```

Owner decision doc:

- [2026-05-03-appdata-owner-decisions.md](/Users/mythic3014/Documents/project/venera/docs/plans/2026-05-03-appdata-owner-decisions.md)

Acceptance tests:

```text
test('appdata audit classifies local history and favorite keys as non-authoritative', () async {});
test('local library loads without appdata local authority keys', () async {});
test('ui preferences remain available from appdata', () async {});
```

Backlog after BUG-A1 phase close:

- future UI-state store migration, optional
- remove legacy appdata residues after migration window

---

## 3. Closed Bug Tracker

### BUG-D2 - Local detail page blocked / not fully canonical-ready

- **Status:** Closed
- **Priority:** P0
- **Area:** Comic detail loader / canonical local detail
- **Commits:** `796f92e`, `Uncommitted / pending commit`

Resolution:

- local detail loader now stays on `UnifiedLocalComicDetailRepository`
- canonical detail VM now exposes shared continue/progress state
- local detail renders imported chapters and progress through the shared detail UI contract
- remote detail path still uses the shared chapters/progress UI contract

Verification:

```text
flutter test test/pages/comic_details_page_unified_test.dart
flutter test test/pages/comic_detail_page_rendering_test.dart
```

### BUG-H1 - History item routes directly to Reader / cover path not canonical

- **Status:** Closed
- **Priority:** P1
- **Area:** History routing / local cover resolution
- **Commits:** `Uncommitted / pending commit`

Resolution:

- `ReaderActivityRepository` path canonicalizes local cover to canonical `file://` path when available
- `HistoryPage` tap now opens detail-first instead of `ReaderWithLoading`
- home history strip tap now opens detail-first
- route progress context is passed as fallback (`chapterId` / `page`)
- history cover resolution respects canonical `file://` / absolute path before legacy fallback provider

Remaining audit:

- `HistoryManager.getRecent()`
- `History.cover` snapshot authority
- `ResumeTargetStore(appdata.implicitData)` authority
- `HistoryStore` legacy naming / canonical routing boundary

Authority note:

- `HistoryManager` remains a legacy compatibility facade
- new UI entrypoints should prefer `ReaderActivityRepository` + canonical detail store over `HistoryManager` authority

Verification:

```text
flutter test test/pages/history_page_test.dart test/pages/history_page_m15_test.dart
```

### BUG-S2 - Custom repository packages not visible / refresh diagnostics insufficient

- **Status:** Closed
- **Priority:** P2
- **Area:** Source repository refresh
- **Commits:** `Uncommitted / pending commit`

Resolution:

- repository section top-level `Refresh` now executes a controller-owned repository refresh command instead of only reloading cached DB state
- refresh-all path now emits `repository.refresh.start` and `repository.refresh.repositoryCount`
- custom repository package list is reloaded after refresh and becomes visible in the review-only `Available Sources` section

Verification:

```text
dart analyze lib/features/sources/comic_source/source_management_controller.dart lib/pages/comic_source_page.dart test/features/source_management/source_management_controller_test.dart test/pages/settings_comic_sources_page_test.dart
flutter test test/features/source_management/source_management_controller_test.dart test/pages/settings_comic_sources_page_test.dart
```

### BUG-R3 - ReaderWithLoading parent identity used unresolved placeholder SourceRef

- **Status:** Closed
- **Priority:** P0
- **Area:** Reader route / parent lifecycle
- **Commit:** `a3cb102 fix(reader): normalize parent tab identity after source resolution`

Resolution:

- added state-level resolved sourceRef retention in `ReaderWithLoading`
- parent diagnostics and `readerChildKey` now use resolved sourceRef id
- parent diagnostics now also land in `readerTrace`

### BUG-D1 - Local list card routed directly to Reader instead of Detail

- **Status:** Closed
- **Priority:** P0
- **Area:** Local library routing / UX
- **Commit:** `e351efe fix(local-library): open detail page from comic cards`

Resolution:

- ordinary local library card click now opens local `ComicDetailPage`
- card heroTag is preserved for detail transition

### BUG-S1 - Source page exposed fake install affordances while install path was disabled

- **Status:** Closed
- **Priority:** P1
- **Area:** Source management UI
- **Commit:** `645a1b1 fix(sources): hide disabled repository install actions`

Resolution:

- `Available Sources` is now review-only while repository install path remains disabled
- removed disabled install button / pending affordance

### CLOSED-I1 - CBZ import blocked by legacy local DB

- **Status:** Closed
- **Commit:** `a67fc9c fix(import): route local comic import through canonical storage`

Result:

CBZ import now uses canonical storage adapter. Legacy local DB no longer blocks import.

### CLOSED-I2 - CBZ zip edge cases

- **Status:** Closed
- **Commit:** `704debd fix(import): harden CBZ zip import edge cases`

Fixed:

- single-image `cover.*` archive now keeps cover as page 1
- destination folder collision fallback
- `cbz_import` cache cleanup on failure

### CLOSED-HERO1 - Duplicate Hero cover tag crash

- **Status:** Closed
- **Commit:** `b2eed4c fix(ui): scope comic cover hero tags by surface`

Fixed:

Duplicate `cover7045321` Hero tag crash.

### CLOSED-C1 - Comic detail chapter controller lifecycle

- **Status:** Closed
- **Commit:** `a723d5b fix(comic-detail): stabilize chapter tab controller and grouped index mapping`

Fixed:

- `TabController` dispose/recreate
- grouped index mapping
- `showAll` reset timing
- unnecessary `setState` for history sync

### CLOSED-R1 - Local reader resume validation

- **Status:** Closed

Fixed:

Local reader resume no longer requires remote-only contract or `pageOrderId`.

### CLOSED-R2 - Reader image observability extraction

- **Status:** Closed

Fixed / added:

- image provider factory extraction
- image bytes loader coverage
- page load controller extraction
- render terminal diagnostics

### CLOSED-R4 - Active tab retention upsert bug

- **Status:** Closed
- **Commit:** `ba0ca25 fix(reader): retain active tab across session upserts`

Fixed:

`upsertReaderSession(activeTabId: null)` no longer clears existing active tab.

---

## 4. Recommended Next Execution Order

1. **BUG-A1** - appdata authority audit

---

## 5. Architecture Target

Detail flow:

```text
Local / History / Remote list item
-> ComicDetailRoute
-> ComicDetailController
-> LocalComicDetailService
-> RemoteComicDetailService
-> ComicDetailViewModel
-> Shared ComicDetailPage UI
-> Continue button / Chapter click
-> ReaderOpenRequest
-> Reader
```

Reader flow:

```text
ReaderOpenRequest
-> resolved SourceRef
-> ReaderWithLoading
-> Reader
-> ReaderImages
```

Reader should not infer missing chapter identity from placeholder `_` when a resolved tab / sourceRef exists.

Source install flow:

```text
Repository refresh
-> list packages for review
-> validate direct URL / config file
-> staged source writer
-> parser/register handoff
-> controller wiring later
-> UI install enablement last
```

---

## 6. Rules Going Forward

1. Do not fix reader by adding more fallback guesses.
2. Do not let local canonical paths depend on legacy local DB availability.
3. Do not expose install buttons before install path is actually enabled.
4. Do not use `pageOrderId` as tab identity.
5. Do not let History/List ordinary tap open Reader directly.
6. Reader should receive a resolved `SourceRef`, not reconstruct one from partial UI state.
7. AppData JSON should keep UI preferences, not migrated local/history/favorites authority.
8. Diagnostics must identify source of truth: canonical DB, legacy bridge, appdata, or runtime adapter.
