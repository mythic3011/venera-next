# Diagnostics Dedupe And Import Lifecycle Review Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make diagnostics/export output decision-useful by grouping duplicated known errors, while reviewing and narrowing the current import lifecycle diff before any lifecycle implementation is accepted.

**Architecture:** Keep two independent lanes. Lane A owns diagnostic grouping and controlled local-missing load state. Lane B starts with a review packet for the current import lifecycle diff, then lands only narrowed lifecycle/import commits after findings are locked. Raw log storage, logger-core dedupe, file locking, writer queues, and log rotation are out of scope. The grouped issue signature must be stable across route instances, and import lifecycle diagnostics must be redacted by construction.

**Tech Stack:** Flutter/Dart, `AppDiagnostics`, legacy `Log`, `/diagnostics` debug exporter, `LoadingState`, canonical local import storage.

---

## Review Findings On The Draft Plan

1. The draft has the right split, but the controlled local-missing state must fit the existing `Res.error(String)` path. `LoadingState` currently turns error strings into `AppLoadError.fromMessage(...)`, then emits `ui.error.visible`; the minimal change is to add a typed `LocalComicMissingLoadError` selected by a stable string code such as `LOCAL_COMIC_MISSING`, not to widen `Res` first.

2. The current uncommitted lifecycle diff is too broad to accept as-is. It mixes detail-page warning behavior, CBZ/PDF import phases, local-download setup, storage preflight/register phases, and test edits. Treat it as review input only.

3. Lifecycle diagnostics must not expand raw path exposure. The current draft diff adds fields such as `sourcePath`, `cachePath`, `rootPath`, and `targetDirectory`. Before landing lifecycle instrumentation, define safe fields: names, source type, operation, import id, stable failure code, and path hashes or basenames where needed.

4. Grouping belongs at the debug/export compatibility layer first. `LogDiagnostics.diagnosticSnapshot()` currently merges session and persisted logs and sorts them together; `/diagnostics` exposes `newestErrors` plus `newestErrorsBySource`. Additive grouping under `logs.groupedIssues` is the low-risk compatibility path.

5. Lane A should absorb `comic_page.dart` local-missing handling. Lane B must not carry detail-page UI semantics, because import lifecycle instrumentation and visible UI error policy are separate owners.

6. Grouping signatures must not include unstable route instance fields such as `routeHash`. `routeHash` can appear in `fields.latestRouteHash` or sample entries, but it must not decide whether two errors belong to the same grouped issue.

7. Lane B has a hard privacy boundary. Absolute paths and path-like fields such as `sourcePath`, `cachePath`, `rootPath`, and `targetDirectory` are forbidden in import lifecycle diagnostics. Use basename, hash, root alias, or stable failure code fields instead.

## Lane A: Diagnostics Dedupe And Controlled Local-Missing State

### Task A1: Add Grouped Legacy-Diagnostic Projection Tests

**Files:**

- Modify: `test/foundation/log_test.dart`
- Modify: `test/foundation/debug_log_exporter_test.dart`

**Steps:**

1. Add a failing unit test that creates one session log and one persisted log representing the same projected structured diagnostic body:
   - level: `error`
   - title/channel: `ui.error`
   - body shape like `[error] ui.error: ui.error.visible errorType=LoadError {"routeHash":123,"sanitizedMessage":"LOCAL_COMIC_MISSING","exceptionType":"LoadError","diagnosticCode":"LOCAL_COMIC_MISSING","pageOwner":"ComicPage"}`
2. Assert the future grouping API returns one grouped issue with `occurrenceCount == 2`.
3. Assert the grouped issue has `sources.session.count == 1` and `sources.persisted.count == 1`.
4. Add a fallback test for non-parseable legacy entries where grouping uses title plus normalized content.
5. Add a `/diagnostics` shape test asserting `logs.groupedIssues` exists while `newestErrors` and `newestErrorsBySource` remain present.

**Run:**

```bash
flutter test test/foundation/log_test.dart test/foundation/debug_log_exporter_test.dart
```

Expected first result: FAIL because `groupedIssues` does not exist.

### Task A2: Implement Additive Grouping In The Log Diagnostics Layer

**Files:**

- Modify: `lib/foundation/diagnostics/log_diagnostics.dart`
- Modify: `lib/foundation/diagnostics/debug_diagnostics_service.dart`

**Implementation Notes:**

- Add immutable DTOs or serialized maps for grouped issues; avoid `dynamic`/`any`.
- Add `groupedIssues` to `LogDiagnosticSnapshot`, derived from the already merged `logs`.
- Keep `logs`, `newestErrors`, and `newestErrorsBySource` unchanged.
- Parse projected structured legacy content from the formatter shape in `diagnostics.dart`: `[level] channel: message errorType=Type {json-data}`.
- Prefer grouping fields from parsed projected data:
  - `message`
  - `diagnosticCode`
  - `sanitizedMessage`
  - `exceptionType`
  - `pageOwner`
  - `tabOwner`
- Do not include `routeHash` in the grouping signature. Preserve route identity only as auxiliary fields such as `latestRouteHash`, `routeHashes`, or `sampleRouteHashes`.
- Normalize `UnknownLoadError` / `LoadError` grouping by preferring parsed `exceptionType` from projected data when present.
- Parse `latestTime` as a timestamp; do not rely on mixed string sorting.
- For non-parseable legacy entries, group by `title` plus normalized `content`.
- Output shape for each issue:
  - `signature`
  - `message`
  - `latestTime`
  - `occurrenceCount`
  - `sources`
  - `latestEntry`
  - `fields`
  - `sampleRouteHashes` when present

**Run:**

```bash
flutter test test/foundation/log_test.dart test/foundation/debug_log_exporter_test.dart
```

Expected final result: PASS.

### Task A3: Add Controlled Load Error Tests

**Files:**

- Modify: `test/components/loading_framework_hardening_test.dart`
- Create or modify focused comic-detail test if an existing local-detail harness already covers `_ComicPageState.loadData`.

**Steps:**

1. Add a widget test where `loadData()` returns `const Res.error('LOCAL_COMIC_MISSING')`.
2. Assert an error UI renders.
3. Assert no `ui.error.visible` event is emitted.
4. Keep the existing test that generic visible errors emit `ui.error.visible`.
5. Add a comic-detail test or source assertion that the local-orphan path returns `LOCAL_COMIC_MISSING` and emits `comic.detail.localMissing`.
6. Assert the controlled local-missing path emits `comic.detail.localMissing` once.
7. Assert the controlled local-missing path does not project a duplicate legacy `ui.error` log entry.

**Run:**

```bash
flutter test test/components/loading_framework_hardening_test.dart
```

Expected first result: FAIL because all `LoadingState` errors currently emit `ui.error.visible`.

### Task A4: Implement Controlled Local-Missing Load State

**Files:**

- Modify: `lib/components/loading.dart`
- Modify: `lib/pages/comic_details_page/comic_page.dart`

**Implementation Notes:**

- Add `bool get emitVisibleDiagnostic` to `AppLoadError`, defaulting to `true` for existing error types.
- Add `LocalComicMissingLoadError`:
  - `diagnosticCode => 'LOCAL_COMIC_MISSING'`
  - `retryable => false`
  - `exportLogsSuggested => false` unless UX explicitly changes later
  - `emitVisibleDiagnostic => false`
  - user-facing text must be localized/descriptive and must not expose the raw `LOCAL_COMIC_MISSING` code
- Update `AppLoadError.fromMessage` to return `LocalComicMissingLoadError` when the message starts with `LOCAL_COMIC_MISSING`.
- Gate `_emitUiErrorVisible(...)` in `LoadingState` and `MultiPageLoadingState` with `appError.emitVisibleDiagnostic`.
- In `comic_page.dart`, keep the structured warning `comic.detail.localMissing`, but return `const Res.error('LOCAL_COMIC_MISSING')` instead of generic text for the missing canonical local row.
- Do not move local-missing behavior into import lifecycle files.
- Generic `LoadError` and unexpected loading failures must continue to emit `ui.error.visible`.

**Run:**

```bash
flutter test test/components/loading_framework_hardening_test.dart
```

Expected final result: PASS.

### Task A5: Update Debug UI Guidance

**Files:**

- Modify: `lib/pages/settings/debug.dart`

**Steps:**

1. Replace the guidance text that points users to mixed `newestErrors`.
2. New guidance should say `logs.groupedIssues` is the primary deduped view and raw `newestErrors` / `newestErrorsBySource` are drill-down compatibility fields.
3. Do not redesign `LogsPage` unless a test proves it consumes `/diagnostics` grouped data directly.

**Run:**

```bash
flutter test test/foundation/debug_log_exporter_test.dart
```

### Lane A Commit Boundary

Commit Lane A as one or two small commits:

```bash
git add lib/foundation/diagnostics/log_diagnostics.dart lib/foundation/diagnostics/debug_diagnostics_service.dart test/foundation/log_test.dart test/foundation/debug_log_exporter_test.dart
git commit -m "feat: group duplicate diagnostics in debug payload"

git add lib/components/loading.dart lib/pages/comic_details_page/comic_page.dart test/components/loading_framework_hardening_test.dart lib/pages/settings/debug.dart
git commit -m "fix: suppress visible diagnostics for controlled local missing"
```

## Lane B: Import Lifecycle Review-First Hardening

### Task B0: Preserve Current Diff As Review Input

**Files To Review:**

- `lib/utils/import_lifecycle.dart`
- `lib/utils/import_comic.dart`
- `lib/utils/cbz.dart`
- `lib/utils/local_import_storage.dart`
- `lib/pages/comic_details_page/comic_page.dart`
- `test/utils/cbz_import_canonical_storage_test.dart`

**Review Packet Must Classify:**

- Accept into lifecycle primitive.
- Accept into import entrypoint instrumentation.
- Move to Lane A.
- Reject or defer because it leaks raw paths, mixes concerns, or is too broad.

**Expected Findings To Lock:**

- `comic_page.dart` warning plus generic `Res.error('Local comic not found')` is insufficient; this belongs to Lane A.
- `ImportLifecycleTrace.start(... sourcePath: file.path ...)` must be changed before landing because raw source paths should not be diagnostics defaults.
- `localDownloads()` needs lifecycle failure coverage for early root-resolution/setup errors before the loading dialog and inner catch path.
- Storage preflight/register phase events should be redacted/hash-safe and should not duplicate domain diagnostics already emitted by `ImportFailure`.

**Output:**

- A review packet in chat or a short doc section with file/line findings before implementation.
- No lifecycle code is committed until this packet is accepted.

**Hard Gate:**

- Tasks B1, B2, and B3 must not start until the B0 review packet is accepted.
- `comic_page.dart` changes discovered in the current diff must be moved to Lane A or rejected before any import lifecycle commit.
- Any lifecycle field carrying an absolute path blocks implementation until replaced with basename/hash/root-alias fields.

### Task B1: Land Lifecycle Primitive Only

**Files:**

- Create or modify: `lib/utils/import_lifecycle.dart`
- Add focused tests in the nearest existing import diagnostics test file, or create `test/utils/import_lifecycle_test.dart` if no suitable file exists.

**Implementation Contract:**

- `ImportLifecycleTrace.start(operation, sourceName, sourceType, data)` emits `import.lifecycle.started`.
- Do not accept `sourcePath`, `cachePath`, `rootPath`, `targetDirectory`, or any absolute-path field as a public parameter.
- Include `importId`, `operation`, `elapsedMs`.
- Provide safe helpers for path-like fields:
  - basename only for display names
  - stable hash for correlation when path identity is required
  - root aliases such as `<APP_DATA>`, `<CACHE>`, or `<IMPORT_ROOT>` when root identity is useful
  - no absolute path by default
- `run()` keeps the trace in a zone.
- `phase()`, `completed()`, and `failed()` preserve the same `importId`.
- `sourceName` is a display basename only and may be redacted later; it must not be a full path.

**Run:**

```bash
flutter test test/utils/import_lifecycle_test.dart
dart analyze lib/utils/import_lifecycle.dart
```

Commit:

```bash
git add lib/utils/import_lifecycle.dart test/utils/import_lifecycle_test.dart
git commit -m "feat: add import lifecycle trace primitive"
```

### Task B2: Instrument Import File Entrypoints Only

**Files:**

- Modify: `lib/utils/import_comic.dart`
- Modify: `lib/utils/cbz.dart`
- Modify tests under `test/utils/` that already cover CBZ/PDF/import entrypoints.

**Implementation Contract:**

- Instrument CBZ, PDF, and generic file import entrypoints with `started`, coarse `phase`, `completed`, and `failed`.
- Use one lifecycle per top-level import. Nested CBZ/PDF helpers may add phases but must not start competing import ids if one exists.
- Do not touch `comic_page.dart`.
- Do not instrument storage preflight/register in this commit.
- Keep existing typed import failures and canonical fail-closed behavior unchanged.

**Run:**

```bash
flutter test test/utils/cbz_import_canonical_storage_test.dart
dart analyze lib/utils/import_comic.dart lib/utils/cbz.dart lib/utils/import_lifecycle.dart
```

Commit:

```bash
git add lib/utils/import_comic.dart lib/utils/cbz.dart test/utils/cbz_import_canonical_storage_test.dart
git commit -m "feat: trace import file lifecycle"
```

### Task B3: Harden Local Downloads Early Failure And Registration Diagnostics

**Files:**

- Modify: `lib/utils/import_comic.dart`
- Modify: `lib/utils/local_import_storage.dart` only if review accepts storage-level phase events.
- Modify focused import tests under `test/utils/`.

**Implementation Contract:**

- `localDownloads()` starts lifecycle before root resolution.
- Root-resolution or root-creation failures emit `import.lifecycle.failed` with the same `importId`.
- Duplicate, missing-files, copy-failed, repair-started/completed/failed, and register-failed diagnostics carry the lifecycle correlation id when inside a lifecycle.
- Domain diagnostic events keep stable `ImportFailure.code`; lifecycle diagnostics describe operation phase and correlation only.
- Use redacted or hashed path fields only.
- If root type checks are needed, use `FileSystemEntity.typeSync(path, followLinks: false)` and treat links as fail-closed unless explicitly approved later.
- If directory scanning is needed, use `Directory.listSync(recursive: false, followLinks: false)` and sort only for deterministic processing; never use filesystem order as page order.

**Run:**

```bash
flutter test test/utils/cbz_import_canonical_storage_test.dart
dart analyze lib/utils/import_comic.dart lib/utils/local_import_storage.dart lib/utils/import_lifecycle.dart
```

Commit:

```bash
git add lib/utils/import_comic.dart lib/utils/local_import_storage.dart test/utils/cbz_import_canonical_storage_test.dart
git commit -m "fix: correlate local import lifecycle failures"
```

## Final Verification

Run only targeted checks for touched surfaces:

```bash
flutter test test/foundation/log_test.dart test/foundation/debug_log_exporter_test.dart test/components/loading_framework_hardening_test.dart test/utils/cbz_import_canonical_storage_test.dart
dart analyze lib/components/loading.dart lib/foundation/diagnostics/log_diagnostics.dart lib/foundation/diagnostics/debug_diagnostics_service.dart lib/pages/comic_details_page/comic_page.dart lib/pages/settings/debug.dart lib/utils/import_lifecycle.dart lib/utils/import_comic.dart lib/utils/cbz.dart lib/utils/local_import_storage.dart
```

Additional grep guards:

```bash
rg 'routeHash.*signature|signature.*routeHash' lib test
rg 'sourcePath|cachePath|rootPath|targetDirectory' lib/utils/import_lifecycle.dart lib/utils/import_comic.dart lib/utils/cbz.dart lib/utils/local_import_storage.dart
rg 'ui.error.visible.*LOCAL_COMIC_MISSING|LOCAL_COMIC_MISSING.*ui.error.visible' lib test
```

Allowed matches must be reviewed manually. Path-like lifecycle matches are only allowed if they are explicit basename/hash/root-alias fields, not raw absolute paths.

If analyzer or tests show unrelated pre-existing failures, capture the exact failure text and do not widen the lane without approval.

## Explicit Out Of Scope

- Logger-core dedupe.
- Raw log storage changes.
- File locking, log rotation, writer queue, or in-process log serialization.
- In-app `LogsPage` redesign unless it is a direct `/diagnostics` consumer.
- Reader/local missing filesystem repair.
- Broad import UI cleanup.
- Any `comic_page.dart` behavior inside Lane B.
- Import lifecycle raw-path logging or report-export privacy redaction; redaction/report bundle work belongs to a separate diagnostics export lane.
