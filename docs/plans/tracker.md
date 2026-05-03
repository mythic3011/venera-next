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

### BUG-D2 - Local detail page blocked / not fully canonical-ready

- **Status:** In progress
- **Priority:** P0
- **Area:** Comic detail loader / canonical local detail

Symptom:

Local and remote share detail UI conceptually, but local detail flow is still only partially completed.

Decision:

```text
ComicDetailPage
-> ComicDetailLoader
-> LocalComicDetailService
-> RemoteComicDetailService
-> ComicDetailViewModel
```

Progress:

- local detail authority hardened to `UnifiedLocalComicDetailRepository`
- generic `App.repositories.comicDetail` removed from local load path
- local detail read request now builds from resolved `SourceRef`
- local detail chapter/read actions bypass ReaderNext dry-run interception
- commit: `796f92e fix(comic-detail): harden local canonical detail authority`

Still open:

- local detail chapters / progress rendering
- shared UI contract still needs full local/remote convergence

Acceptance tests:

```text
testWidgets('local comic detail loads from canonical local detail repository', (tester) async {});
testWidgets('local comic detail shows imported chapters', (tester) async {});
testWidgets('remote comic detail still loads from source adapter', (tester) async {});
```

### BUG-H1 - History item routes directly to Reader / cover path not canonical

- **Status:** Open
- **Priority:** P1
- **Area:** History routing / local cover resolution

Symptoms:

- History item cover fails or renders blank.
- History item click goes directly to reader.
- User cannot inspect detail/chapter context before reading.

Expected behavior:

```text
History item click
-> Comic Detail Page with progress context
-> Continue reading / chapter click
-> Reader
```

Fix direction:

- History local item uses canonical local cover path
- History click opens detail page, not reader
- Pass progress context: chapterId / page / pageOrderId where available

Acceptance tests:

```text
testWidgets('history local comic tap opens detail page instead of reader', (tester) async {});
testWidgets('history local comic cover resolves from canonical local detail cover path', (tester) async {});
testWidgets('history detail route carries chapter and page progress context', (tester) async {});
```

### BUG-S2 - Custom repository packages not visible / refresh diagnostics insufficient

- **Status:** Open
- **Priority:** P2
- **Area:** Source repository refresh

Symptom:

User repository package does not appear after refresh.

Current state:

- base review-only UI is in place
- refresh diagnostics added:
  - `repository.refresh.package.count`
  - `repository.refresh.package.skipped`
  - `repository.refresh.package.sourceUrl`
  - `repository.refresh.package.schemaError`
- commit: `645a1b1 fix(sources): hide disabled repository install actions`

Still open:

- visibility bug for custom repositories still not root-caused
- start / repository-count diagnostics are still missing
- package collision / filter path still needs proof

Acceptance tests:

```text
test('repository refresh emits package count diagnostic', () async {});
test('repository refresh emits schema error diagnostic for invalid package', () async {});
test('repository refresh records skipped package reason', () async {});
```

### BUG-A1 - application data.json authority still mixed with DB authority

- **Status:** Open
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

Acceptance tests:

```text
test('appdata audit classifies local history and favorite keys as non-authoritative', () async {});
test('local library loads without appdata local authority keys', () async {});
test('ui preferences remain available from appdata', () async {});
```

---

## 3. Closed Bug Tracker

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

### CLOSED-R3 - Active tab retention upsert bug

- **Status:** Closed
- **Commit:** `ba0ca25 fix(reader): retain active tab across session upserts`

Fixed:

`upsertReaderSession(activeTabId: null)` no longer clears existing active tab.

---

## 4. Recommended Next Execution Order

1. **BUG-D2** - finish local canonical detail branch
2. **BUG-H1** - history routing and cover path
3. **BUG-S2** - repository refresh diagnostics and custom repo visibility
4. **BUG-A1** - appdata authority audit

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
