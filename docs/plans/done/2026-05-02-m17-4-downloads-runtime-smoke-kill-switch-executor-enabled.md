# M17.4 Downloads Runtime Smoke + Kill-Switch with Executor Enabled

Goal:

- Verify the downloads ReaderNext executor-injection path behaves safely in app-level smoke tests.
- Prove downloads kill-switch rollback works after executor injection.
- Keep actual ReaderNext navigation wiring out of this milestone.

Scope:

- smoke/integration tests only
- downloads entrypoint only
- executor-injection path only
- no actual ReaderNext navigation executor implementation
- no downloads page ReaderNext runtime import
- no downloads page ReaderNext presentation screen/page import
- no downloads page executor implementation import
- no identity reconstruction
- no fallback after blocked downloads decision
- no history/favorites behavior change

## Hard Rules

1. `reader_next_downloads_enabled=false` returns downloads opens to explicit legacy route.
2. Kill-switch affects route selection only.
3. Kill-switch must not mutate M14 readiness artifact, M17 preflight state, SourceRef snapshots, downloads rows, history rows, or favorites rows.
4. `reader_next_downloads_enabled=true` must still pass M14 readiness + M17 explicit-identity preflight.
5. `readerNextEligible` must dispatch injected executor exactly once.
6. Injected executor input must be bridge/controller-produced validated output only.
7. Downloads page must not pass raw identity/path fields to executor.
8. Downloads page must not construct `ReaderNextOpenRequest` directly.
9. Downloads page must not construct `SourceRef` directly.
10. Downloads page must not import ReaderNext runtime, presentation screen/page, or executor implementation classes.
11. Blocked downloads rows are terminal: no legacy fallback and no executor call.
12. `legacyExplicit` calls explicit legacy route exactly once and executor zero times.
13. Local/cache/archive/file paths remain storage-only and must not affect route identity.
14. Diagnostics must include route decision, schema version, current validation code, blocked reason, and redacted record/session/candidate/fingerprint fields.
15. Diagnostics must not expose raw canonical IDs, upstream IDs, chapter IDs, local paths, cache paths, archive paths, filenames, URLs, cookies, headers, or tokens.
16. Actual ReaderNext navigation wiring is forbidden in M17.4.
17. History/favorites route behavior must remain unchanged.

## Route Behavior

| State                                                                 | Expected Decision           | Legacy Callback | Injected Executor | Blocked State    |
| --------------------------------------------------------------------- | --------------------------- | --------------- | ----------------- | ---------------- |
| `reader_next_downloads_enabled=false`                                 | `legacyExplicit`            | called once     | not called        | not called       |
| `reader_next_downloads_enabled=true` + downloads eligible             | `readerNextEligible`        | not called      | called once       | not called       |
| `reader_next_downloads_enabled=true` + downloads blocked              | `blocked`                   | not called      | not called        | rendered/emitted |
| downloads local/cache/archive path changed but explicit identity same | unchanged decision          | unchanged       | unchanged         | unchanged        |
| history/favorites route attempts                                      | unchanged existing behavior | unchanged       | unchanged         | unchanged        |

## Kill-Switch Contract

Kill-switch means:

- set `reader_next_downloads_enabled=false`
- downloads open returns to explicit legacy route
- injected executor is not called for downloads
- actual ReaderNext navigation is not called for downloads
- M14 readiness artifact is not changed
- M17 downloads preflight state is not changed
- SourceRef snapshots are not changed
- downloads/history/favorites rows are not changed
- history/favorites route behavior remains unchanged

Kill-switch does not mean:

- fallback after a blocked ReaderNext decision
- accepting malformed SourceRef
- bypassing current-row validation
- changing M14 readiness decisions
- changing M17 explicit identity rules
- enabling actual navigation wiring
- enabling or disabling other entrypoints

## Executor Smoke Contract

The injected executor may receive only bridge/controller-produced validated output.

The downloads page must not pass these raw values to executor:

- raw `recordId`
- raw `sourceKey`
- raw `canonicalComicId`
- raw `upstreamComicRefId`
- raw `chapterRefId`
- raw local file path
- raw cache path
- raw archive path
- raw filename
- raw URL
- M14 readiness artifact data
- M17 preflight internals

The injected executor in M17.4 is a smoke-test seam only. It must not navigate to a ReaderNext screen.

## Tasks

| Task ID  | Deliverable                                                                                                                   | Verification              |
| -------- | ----------------------------------------------------------------------------------------------------------------------------- | ------------------------- |
| M17.4-T1 | app-level smoke: downloads flag off uses explicit legacy route                                                                | widget/integration test   |
| M17.4-T2 | app-level smoke: downloads flag on + eligible dispatches injected executor exactly once                                       | widget/integration test   |
| M17.4-T3 | app-level smoke: downloads flag on + blocked renders blocked state and does not fallback                                      | widget/integration test   |
| M17.4-T4 | kill-switch test: disabling `reader_next_downloads_enabled` stops executor attempts without mutating readiness/identity state | controller/widget test    |
| M17.4-T5 | diagnostic smoke: `legacyExplicit`, `readerNextEligible`, and `blocked` decisions emit redacted packets                       | diagnostic test           |
| M17.4-T6 | guard: eligible executor input is bridge/controller-produced and contains no raw identity/path fields                         | controller test           |
| M17.4-T7 | authority guard: downloads still have no actual ReaderNext navigation wiring                                                  | grep-backed test          |
| M17.4-T8 | regression guard: history/favorites behavior unchanged                                                                        | authority/regression test |

## Required Tests

```dart
testWidgets('downloads executor smoke: flag off uses explicit legacy route', (tester) async {
  // reader_next_downloads_enabled=false
  // expect routeDecision=legacyExplicit
  // expect legacy callback count == 1
  // expect injected executor count == 0
});

testWidgets('downloads executor smoke: flag on eligible dispatches executor once', (tester) async {
  // valid explicit SourceRef identity
  // reader_next_downloads_enabled=true
  // M14 downloadsReady=true
  // M17 preflight valid
  // expect routeDecision=readerNextEligible
  // expect injected executor count == 1
  // expect legacy callback count == 0
});

testWidgets('downloads executor smoke: blocked row does not fallback', (tester) async {
  // missing SourceRef / stale fingerprint / canonical leak / malformed SourceRef
  // expect routeDecision=blocked
  // expect blocked state
  // expect legacy callback count == 0
  // expect injected executor count == 0
});

test('downloads kill-switch does not mutate readiness or identity state after executor injection', () {
  // capture M14/M17 decision inputs and SourceRef snapshot
  // toggle reader_next_downloads_enabled=false
  // assert captured readiness/preflight/SourceRef state unchanged
});

test('downloads diagnostics are redacted for all executor-enabled route decisions', () {
  // emit legacyExplicit, readerNextEligible, blocked packets
  // expect raw canonical/upstream/chapter/path/url/token/header values absent
  // expect redacted/hash fields only
});

test('downloads executor input is bridge produced and redacted', () {
  // eligible dispatch reaches injected executor
  // expect no raw canonical/upstream/chapter/path/url fields in page-provided payload
});
```

## Authority Guards

Required guard coverage:

- downloads page remains free of ReaderNext runtime imports.
- downloads page remains free of ReaderNext presentation screen/page imports.
- downloads page remains free of executor implementation imports.
- downloads page does not construct `ReaderNextOpenRequest`.
- downloads page does not construct `SourceRef`.
- downloads page does not parse or derive canonical/upstream/chapter IDs from local/cache/archive/file paths.
- no actual downloads navigation executor wiring exists in M17.4.
- no blocked branch calls legacy route.
- no diagnostics expose raw canonical/upstream/chapter/path/url/token/header values.
- history/favorites route behavior remains unchanged.

Suggested guard commands:

```bash
rg -n "features/reader_next/(runtime|presentation)|ReaderNext.*Page|ReaderNext.*Screen|DownloadsReaderNextNavigation" \
  lib/pages/downloading_page.dart lib/pages/local_comics_page.dart \
  -g '!*.g.dart'

rg -n "SourceRef\\.|ReaderNextOpenRequest\\(|upstreamComicRefId|chapterRefId|fromLegacyRemote|open.*ReaderNext|route.*ReaderNext" \
  lib/pages/downloading_page.dart lib/pages/local_comics_page.dart \
  -g '!*.g.dart'

rg -n "blocked[\\s\\S]{0,240}openLegacy|openLegacy[\\s\\S]{0,240}blocked" \
  lib/features/reader_next/bridge lib/pages/downloading_page.dart lib/pages/local_comics_page.dart test/features/reader_next test/pages \
  -g '!*.g.dart'
```

Expected:

- no downloads page identity construction.
- no downloads page ReaderNext runtime/screen/navigation implementation imports.
- no actual downloads navigation wiring.
- no blocked-to-legacy branch.
- no raw identity/path leakage in diagnostics.

## Verification Commands

```bash
flutter test test/pages/downloads_page_m17_4_test.dart
flutter test test/pages/downloads_page_m17_3_test.dart
flutter test test/features/reader_next/bridge/*downloads*
flutter test test/features/reader_next/runtime/*authority*
dart analyze lib/features/reader_next/bridge lib/features/reader_next/preflight lib/pages/downloading_page.dart lib/pages/local_comics_page.dart test/features/reader_next test/pages/downloads_page_m17_4_test.dart
git diff --check
```

## M17.4 Closeout Evidence

M17.4 completed as downloads executor-enabled runtime smoke + kill-switch verification only.

Verified:

- flag off downloads open uses explicit legacy route with `legacyExplicit`
- flag on + eligible downloads open dispatches injected executor exactly once
- flag on + blocked downloads open is terminal: no legacy fallback and no executor call
- kill-switch does not mutate M14 readiness, M17 preflight, SourceRef, downloads, history, or favorites state
- executor input comes only from bridge/controller-produced result
- diagnostics cover `legacyExplicit`, `readerNextEligible`, and `blocked`
- diagnostics are redacted by default
- downloads pages remain free of ReaderNext runtime/presentation/navigation implementation imports
- actual downloads ReaderNext navigation wiring was not introduced
- history/favorites behavior remains unchanged

Final verification:

1. `flutter test test/pages/downloads_page_m17_4_test.dart`
   - Result: All tests passed (+6)
2. `flutter test test/pages/downloads_page_m17_3_test.dart`
   - Result: All tests passed (+5)
3. `flutter test test/features/reader_next/bridge/*downloads*`
   - Result: All tests passed (+5)
4. `flutter test test/features/reader_next/runtime/*authority*`
   - Result: All tests passed (+23)
5. `dart analyze lib/features/reader_next/bridge lib/features/reader_next/preflight lib/pages/downloading_page.dart lib/pages/local_comics_page.dart test/features/reader_next test/pages/downloads_page_m17_4_test.dart`
   - Result: No issues found
6. `git diff --check`
   - Result: clean, no output

## Exit Criteria

- app-level downloads smoke proves flag-off explicit legacy route.
- app-level downloads smoke proves flag-on eligible route dispatches injected executor exactly once.
- app-level downloads smoke proves blocked rows are terminal and do not fallback.
- kill-switch does not mutate M14/M17 readiness or identity state after executor injection.
- eligible executor input is bridge/controller-produced and validated.
- diagnostics are emitted and redacted for all three decision classes.
- actual downloads navigation wiring remains disabled.
- history/favorites behavior remains unchanged.
