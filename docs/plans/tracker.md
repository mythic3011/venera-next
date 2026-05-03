# Venera Migration Timeline + Bug Tracker

0. Current Decision Snapshot

Main decision

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

Remote decision

Remote legacy source runtime remains for now.

Remote source system will be refactored later. Do not remove remote legacy source adapter yet.

UI decision

Local and remote should share the same UI contract:

Shared UI
-> Loader / Controller
-> Local service branch
-> Remote service branch
-> normalized ViewModel
-> ReaderOpenRequest only when user explicitly reads a chapter

Do not maintain separate local detail page and remote detail page unless the UI layout is genuinely different.

⸻

1. Timeline So Far

Phase A — Source repository / Direct JS install lane

Lane Status Notes
M26.2-F1/F2/F3 Closed Source repository registry, diagnostics, redaction, typed URL failures
D1 Closed Direct JS validation-only; no install/write path
D2 Closed UI validate-only dialog; no install/write path
D3a Closed Skeleton contract tests only
D3c0 Closed Installed source authority inventory
D3c1 Closed Minimal write adapter implementation plan only
D3c2 Closed Guard command/tests; no write
D3c3 Closed Staged filesystem tests only
D3c4 Closed DirectJsStagedSourceWriter hardening
D3c5 Closed Parser/register handoff after staged commit
D3c full write path Not started Controller wiring, UI install enablement, provenance/hash still pending

Important boundary:

Source install UI must not expose fake install buttons while install path is disabled.

⸻

Phase B — Local reader black-screen investigation

Lane Status Findings
R-local-1 Closed Local resume validation fixed; local pageOrderId == null no longer blocks resume
R-img-1 Closed Extracted image provider factory
R-img-2 Closed Image bytes loader already extracted / diagnostics covered
R-img-3 Closed Extracted page load controller without moving UI state
R-img-4 Closed Added render terminal diagnostics
R-shell-1 Closed Active tab retention fixed; snapshot blind spot fixed
R-route-1 Diagnostic Parent route/unmount diagnostics added
R-route-3 Closed Parent expected tab identity normalized to resolved sourceRef after loadData

Key evidence:

ReaderWithLoading.buildFrame expectedReaderTabId = local:local:1:\_
Reader.open expectedReaderTabId = local:local:1:1:**imported**
activeReaderTabId = local:local:1:1:**imported**

Conclusion:

Reader data path is mostly healthy:

- page list loads
- provider created
- image bytes loaded
- decode succeeds

Remaining issue is parent identity / routing / entrypoint, not image IO.

⸻

Phase C — Import canonical migration

Lane Status Notes
I-local-import-1 Closed CBZ import now routes through canonical storage; legacy local DB no longer required precondition
I-zip-1 Closed CBZ edge cases fixed: single cover page, folder collision, cache cleanup

Important decision:

canonical local storage unavailable -> fail closed
legacy local DB unavailable -> must not block canonical import

⸻

Phase D — Hero / UI crash investigation

Lane Status Notes
UI-hero-1/2 Closed Cover Hero tags scoped by surface; duplicate cover7045321 crash fixed

Important finding:

Duplicate Hero tag can masquerade as reader lifecycle / black-screen bug because Flutter route transition throws and then Reader gets disposed.

⸻

Phase E — Comic detail maintenance

Lane Status Notes
Chapters lifecycle slice Closed TabController lifecycle fixed, grouped index mapping fixed, showAll reset narrowed

⸻

2. Active Bug Tracker

Critical / Current Blockers

BUG-R3 — ReaderWithLoading parent identity uses unresolved placeholder SourceRef

Status: Closed
Priority: P0
Area: Reader route / parent lifecycle
Files likely involved:

- lib/features/reader/presentation/loading.dart

Symptom:

Local reader loads and decodes pages, then gets disposed shortly after.

Evidence:

ReaderWithLoading.buildFrame:
expectedReaderTabId = local:local:1:\_
activeReaderTabId = local:local:1:1:**imported**
retainedTab = false
Reader.open:
expectedReaderTabId = local:local:1:1:**imported**

Root cause hypothesis:

ReaderWithLoading diagnostics / parent identity uses fallback SourceRef.fromLegacy(...) before resolved local chapter source ref is available. This creates placeholder chapter id \_.

Resolution:

- Added state-level resolved sourceRef retention in `ReaderWithLoading`
- parent diagnostics and `readerChildKey` now use resolved sourceRef id
- parent diagnostics now also land in `readerTrace`

Commit:

- `a3cb102 fix(reader): normalize parent tab identity after source resolution`

Acceptance tests:

test('ReaderWithLoading diagnostics use resolved local imported sourceRef after loadData', () async {});
test('ReaderWithLoading content branch retainedTab is true for local imported active tab', () async {});
test('ReaderWithLoading readerChildKey does not use placeholder chapter id after resume resolution', () async {});

⸻

BUG-D1 — Local list card routes directly to Reader instead of Detail

Status: Closed
Priority: P0
Area: Local library routing / UX

Symptom:

Clicking local comic card opens reader directly.

Expected behavior:

Local comic card click
-> Comic Detail Page
-> chapter/read action
-> Reader

Why it matters:

A comic may have chapters. Direct reader entry hides context, chapter list, tags, and progress.

Resolution:

- Ordinary local library card click now opens local `ComicDetailPage`
- card heroTag is preserved for detail transition

Commit:

- `e351efe fix(local-library): open detail page from comic cards`

Acceptance tests:

testWidgets('local library comic card opens detail page instead of reader', (tester) async {});
testWidgets('local comic card does not invoke ReaderWithLoading directly', (tester) async {});
testWidgets('ReaderNext dry-run does not intercept local detail navigation', (tester) async {});

⸻

BUG-S1 — Source page exposes fake install affordances while install path is disabled

Status: Closed
Priority: P1
Area: Source management UI

Resolution:

- Available Sources is now review-only while repository install path remains disabled
- Removed disabled install button / pending affordance
- Added refresh diagnostics:
  - `repository.refresh.package.count`
  - `repository.refresh.package.skipped`
  - `repository.refresh.package.sourceUrl`
  - `repository.refresh.package.schemaError`

Commit:

- `645a1b1 fix(sources): hide disabled repository install actions`

⸻

BUG-D2 — Local detail page blocked / not canonical-ready

Status: In progress
Priority: P0
Area: Comic detail loader / canonical local detail

Symptom:

Local and remote share detail UI conceptually, but local detail path is blocked or incomplete.

Decision:

Use one shared detail UI with loader/service branch below it.

ComicDetailPage
-> ComicDetailLoader
-> LocalComicDetailService
-> RemoteComicDetailService
-> ComicDetailViewModel

Progress:

- local detail authority hardened to `UnifiedLocalComicDetailRepository`
- generic `App.repositories.comicDetail` removed from local load path

Still open:

- UI route from local card to detail
- local detail chapters/progress rendering
- chapter/read action builds resolved local SourceRef

Current fix direction:

- Local branch uses UnifiedLocalComicDetailRepository
- Remote branch uses ComicSource adapter
- UI consumes normalized ComicDetailViewModel only
- Local detail shows cover/tags/chapters/progress

Acceptance tests:

testWidgets('local comic detail loads from canonical local detail repository', (tester) async {});
testWidgets('local comic detail shows imported chapters', (tester) async {});
testWidgets('remote comic detail still loads from source adapter', (tester) async {});

⸻

BUG-H1 — History item routes directly to Reader / cover path not canonical

Status: Open
Priority: P1
Area: History routing / local cover resolution

Symptoms:

- History item cover fails or renders blank.
- History item click goes directly to reader.
- User cannot inspect detail/chapter context before reading.

Expected behavior:

History item click
-> Comic Detail Page with progress context
-> Continue reading / chapter click
-> Reader

Fix direction:

- History local item uses canonical local cover path
- History click opens detail page, not reader
- Pass progress context: chapterId/page/pageOrderId where available

Acceptance tests:

testWidgets('history local comic tap opens detail page instead of reader', (tester) async {});
testWidgets('history local comic cover resolves from canonical local detail cover path', (tester) async {});
testWidgets('history detail route carries chapter and page progress context', (tester) async {});

⸻

BUG-S1 — Source page exposes disabled install UI as fake functionality

Status: Open
Priority: P1
Area: Source management UI

Symptoms:

- Refresh loads repository packages.
- Available Sources list shows multiple disabled Install pending buttons.
- User sees fake install workflow even though D3 full write path is not enabled.

Decision:

Until install path is complete, Source page should be input/validate/manage only.

Fix direction:

- Hide install buttons while install path disabled
- Show repository packages as review-only diagnostics, or hide Available Sources entirely
- Keep Manage Repositories / Refresh / Validate Direct URL
- Add copy: Repository packages are listed for review only. Install support is not enabled yet.

Acceptance tests:

testWidgets('source page does not show install pending buttons when install path disabled', (tester) async {});
testWidgets('source page keeps repository manage refresh and validate actions visible', (tester) async {});
testWidgets('source page marks repository packages as review only before install enablement', (tester) async {});

⸻

BUG-S2 — Custom repository packages not visible / refresh diagnostics insufficient

Status: Open
Priority: P2
Area: Source repository refresh

Symptom:

User repository package does not appear after refresh.

Unknowns:

- Was repository URL saved?
- Was refresh successful?
- Did package schema fail validation?
- Was package skipped due to key/collision/status?

Fix direction:

Add diagnostics:

repository.refresh.start
repository.refresh.repository.count
repository.refresh.package.count
repository.refresh.package.skipped
repository.refresh.package.schemaError
repository.refresh.package.sourceUrl

Acceptance tests:

test('repository refresh emits package count diagnostic', () async {});
test('repository refresh emits schema error diagnostic for invalid package', () async {});
test('repository refresh records skipped package reason', () async {});

⸻

BUG-A1 — application data.json authority still mixed with DB authority

Status: Open
Priority: P2
Area: AppData / settings authority

Problem:

Canonical DB exists, but application data.json is still created/used. Need to distinguish valid UI preferences from migrated data authority.

Do not delete blindly.

Fix direction:

- Audit appdata.json keys
- Classify:
  - UI preferences: keep in AppData JSON
  - local/history/favorites/source authority: move to DB or mark legacy bridge
  - migration-only keys: read-only / cleanup later
- Add guard that local canonical domains do not require appdata JSON as authority

Acceptance tests:

test('appdata audit classifies local history and favorite keys as non-authoritative', () async {});
test('local library loads without appdata local authority keys', () async {});
test('ui preferences remain available from appdata', () async {});

⸻

3. Closed Bug Tracker

CLOSED-I1 — CBZ import blocked by legacy local DB

Status: Closed
Commit: a67fc9c fix(import): route local comic import through canonical storage

Result:

CBZ import now uses canonical storage adapter. Legacy local DB no longer blocks import.

⸻

CLOSED-I2 — CBZ zip edge cases

Status: Closed
Commit: 704debd import zip hardening

Fixed:

- single-image cover.\* archive now keeps cover as page 1
- destination folder collision fallback
- cbz_import cache cleanup on failure

⸻

CLOSED-HERO1 — Duplicate Hero cover tag crash

Status: Closed
Commit: b2eed4c fix(ui): scope comic cover hero tags by surface

Fixed:

Duplicate cover7045321 Hero tag crash.

⸻

CLOSED-C1 — Comic detail chapter controller lifecycle

Status: Closed
Commit: a723d5b comic detail chapters lifecycle

Fixed:

- TabController dispose/recreate
- grouped index mapping
- showAll reset timing
- unnecessary setState for history sync

⸻

CLOSED-R1 — Local reader resume validation

Status: Closed

Fixed:

Local reader resume no longer requires remote-only contract or pageOrderId.

⸻

CLOSED-R2 — Reader image observability extraction

Status: Closed

Fixed / added:

- image provider factory extraction
- image bytes loader coverage
- page load controller extraction
- render terminal diagnostics

⸻

CLOSED-R3 — Active tab retention upsert bug

Status: Closed
Commit: ba0ca25 fix(reader): retain active tab across session upserts

Fixed:

upsertReaderSession(activeTabId: null) no longer clears existing active tab.

⸻

4. Recommended Next Execution Order

Step 1 — Fix ReaderWithLoading resolved SourceRef mismatch

Bug: BUG-R3

Reason:

It is small, localized, and directly proven by trace.

Expected result:

ReaderWithLoading.buildFrame expectedReaderTabId == Reader.open expectedReaderTabId
retainedTab=true
readerChildKey uses local:local:1:1:**imported**

⸻

Step 2 — Stop direct reader entry from Local list

Bug: BUG-D1

Reason:

Correct product flow is detail-first.

Expected result:

Local card click -> Comic Detail

⸻

Step 3 — Build local canonical detail branch

Bug: BUG-D2

Reason:

Local cannot become first-class until detail page works.

Expected result:

Local detail displays cover, tags, chapters, progress

⸻

Step 4 — Fix History routing and cover path

Bug: BUG-H1

Reason:

History is currently another direct-reader entrypoint and has cover mapping issue.

⸻

Step 5 — Source page stop exposing fake install UI

Bug: BUG-S1

Reason:

Current UI advertises disabled functionality.

⸻

Step 6 — Source repository refresh diagnostics

Bug: BUG-S2

Reason:

Needed to debug why custom repo package is missing.

⸻

Step 7 — AppData authority audit

Bug: BUG-A1

Reason:

Must be audited before deletion.

⸻

5. Architecture Target

Detail flow

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

Reader flow

ReaderOpenRequest
-> resolved SourceRef
-> ReaderWithLoading
-> Reader
-> ReaderImages

Reader should not infer missing chapter identity from placeholder \_ when a resolved tab/source ref exists.

Source install flow

Repository refresh
-> list packages for review
-> validate direct URL / config file
-> staged source writer
-> parser/register handoff
-> controller wiring later
-> UI install enablement last

⸻

6. Rules Going Forward

1. Do not fix reader by adding more fallback guesses.
1. Do not let local canonical paths depend on legacy local DB availability.
1. Do not expose install buttons before install path is actually enabled.
1. Do not use pageOrderId as tab identity.
1. Do not let History/List ordinary tap open Reader directly.
1. Reader should receive a resolved SourceRef, not reconstruct one from partial UI state.
1. AppData JSON should keep UI preferences, not migrated local/history/favorites authority.
1. Diagnostics must identify source of truth: canonical DB, legacy bridge, appdata, or runtime adapter.
