# M17.2 Downloads Runtime Smoke + Kill-Switch Verification

Goal:

- Verify the downloads ReaderNext controller-only path behaves safely in app-level smoke tests.
- Prove downloads kill-switch rollback works without touching M14/M17 readiness or identity state.
- Keep downloads ReaderNext executor/navigation wiring disabled.

Scope:

- smoke/integration tests only
- downloads entrypoint only
- controller/prepared-only path only
- no downloads executor wiring
- no downloads ReaderNext navigation wiring
- no identity reconstruction
- no fallback after blocked downloads decision
- no history/favorites behavior change

## Hard Rules

1. `reader_next_downloads_enabled=false` returns downloads opens to explicit legacy route.
2. Kill-switch affects route selection only.
3. Kill-switch must not mutate M14 readiness artifact, M17 preflight state, SourceRef snapshots, downloads rows, history rows, or favorites rows.
4. `reader_next_downloads_enabled=true` must still pass M14 readiness + M17 explicit-identity preflight.
5. `readerNextEligible` remains prepared-only in M17.2.
6. `readerNextEligible` must not call executor or navigate to ReaderNext.
7. `readerNextEligible` must not expose a `ReaderNextOpenRequest` to downloads page code.
8. Blocked downloads rows are terminal: no legacy fallback and no executor call.
9. Downloads identity remains explicit-source-ref based; no local/cache/archive/file path may influence route identity.
10. Diagnostics must include route decision, schema version, current validation code, blocked reason, and redacted record/session/candidate/fingerprint fields.
11. Diagnostics must not expose raw canonical IDs, upstream IDs, chapter IDs, local paths, cache paths, archive paths, filenames, URLs, cookies, headers, or tokens.
12. Downloads page must remain free of ReaderNext runtime/screen/executor implementation imports.
13. History/favorites route behavior must remain unchanged.

## Tasks

| Task ID  | Deliverable                                                                                                                     | Verification              |
| -------- | ------------------------------------------------------------------------------------------------------------------------------- | ------------------------- |
| M17.2-T1 | app-level smoke: downloads flag off uses explicit legacy route                                                                  | widget/integration test   |
| M17.2-T2 | app-level smoke: downloads flag on + eligible returns prepared-only `readerNextEligible`                                        | widget/integration test   |
| M17.2-T3 | app-level smoke: downloads flag on + blocked renders blocked state and does not fallback                                        | widget/integration test   |
| M17.2-T4 | kill-switch test: disabling `reader_next_downloads_enabled` stops ReaderNext attempts without mutating readiness/identity state | controller/widget test    |
| M17.2-T5 | diagnostic smoke: `legacyExplicit`, `readerNextEligible`, and `blocked` decisions emit redacted packets                         | diagnostic test           |
| M17.2-T6 | guard: eligible prepared output still exposes no `ReaderNextOpenRequest`                                                        | controller test           |
| M17.2-T7 | authority guard: downloads still have no ReaderNext executor/navigation wiring                                                  | grep-backed test          |
| M17.2-T8 | regression guard: history/favorites behavior unchanged                                                                          | authority/regression test |

## Smoke Decision Matrix

| State                                                                 | Expected Decision           | Legacy Callback | Executor   | Blocked/Prepared State   |
| --------------------------------------------------------------------- | --------------------------- | --------------- | ---------- | ------------------------ |
| `reader_next_downloads_enabled=false`                                 | `legacyExplicit`            | called once     | not called | not called               |
| `reader_next_downloads_enabled=true` + downloads eligible             | `readerNextEligible`        | not called      | not called | prepared/diagnostic only |
| `reader_next_downloads_enabled=true` + downloads blocked              | `blocked`                   | not called      | not called | blocked state            |
| downloads local/cache/archive path changed but explicit identity same | unchanged decision          | unchanged       | not called | unchanged                |
| history/favorites route attempts                                      | unchanged existing behavior | unchanged       | unchanged  | unchanged                |

## Kill-Switch Contract

Kill-switch means:

- set `reader_next_downloads_enabled=false`
- downloads open returns to explicit legacy route
- ReaderNext executor/navigation is not called for downloads
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
- enabling executor/navigation wiring
- enabling or disabling other entrypoints

## Required Tests

```dart
testWidgets('downloads smoke: flag off uses explicit legacy route', (tester) async {
  // reader_next_downloads_enabled=false
  // expect routeDecision=legacyExplicit
  // expect legacy callback count == 1
  // expect executor/navigation count == 0
});

testWidgets('downloads smoke: flag on eligible is prepared only', (tester) async {
  // valid explicit SourceRef identity
  // reader_next_downloads_enabled=true
  // M14 downloadsReady=true
  // M17 preflight valid
  // expect routeDecision=readerNextEligible
  // expect no executor/navigation call
  // expect no ReaderNextOpenRequest exposed to page
});

testWidgets('downloads smoke: blocked row does not fallback', (tester) async {
  // missing SourceRef / stale fingerprint / canonical leak / malformed SourceRef
  // expect routeDecision=blocked
  // expect blocked state
  // expect legacy callback count == 0
  // expect executor/navigation count == 0
});

test('downloads kill-switch does not mutate readiness or identity state', () {
  // capture M14/M17 decision inputs and SourceRef snapshot
  // toggle reader_next_downloads_enabled=false
  // assert captured readiness/preflight/SourceRef state unchanged
});

test('downloads diagnostics are redacted for all route decisions', () {
  // emit legacyExplicit, readerNextEligible, blocked packets
  // expect raw canonical/upstream/chapter/path/url/token/header values absent
  // expect redacted/hash fields only
});

test('downloads eligible prepared output still does not expose ReaderNextOpenRequest', () {
  // expect decision=readerNextEligible
  // expect prepared/diagnostic result only
  // expect no ReaderNextOpenRequest payload
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
- no downloads executor/navigation wiring exists in M17.2.
- no blocked branch calls legacy route.
- no diagnostics expose raw canonical/upstream/chapter/path/url/token/header values.
- history/favorites route behavior remains unchanged.

Suggested guard commands:

```bash
rg -n "features/reader_next/(runtime|presentation)|ReaderNext.*Page|ReaderNext.*Screen|DownloadsReaderNext.*Executor|DownloadsReaderNextNavigation" \
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
- no downloads page ReaderNext runtime/screen/executor implementation imports.
- no downloads executor/navigation wiring.
- no blocked-to-legacy branch.
- no raw identity/path leakage in diagnostics.

## Verification Commands

```bash
flutter test test/pages/downloads_page_m17_2_test.dart
flutter test test/features/reader_next/bridge/*downloads*
flutter test test/features/reader_next/runtime/*authority*
dart analyze lib/features/reader_next/bridge lib/features/reader_next/preflight lib/pages/downloading_page.dart lib/pages/local_comics_page.dart test/features/reader_next test/pages/downloads_page_m17_2_test.dart
git diff --check
```

## M17.2 Closeout Evidence

M17.2 completed as downloads runtime smoke + kill-switch verification only.

Verified:

- flag off downloads open uses explicit legacy route with `legacyExplicit`
- flag on + eligible downloads open returns `readerNextEligible` as prepared-only
- flag on + blocked downloads open is terminal: no legacy fallback and no executor/navigation call
- kill-switch does not mutate M14 readiness, M17 preflight, SourceRef, downloads, history, or favorites state
- diagnostics cover `legacyExplicit`, `readerNextEligible`, and `blocked`
- diagnostics are redacted by default
- eligible result does not expose `ReaderNextOpenRequest`
- downloads executor/navigation wiring remains disabled

Final verification:

1. `flutter test test/pages/downloads_page_m17_2_test.dart`
   - Result: All tests passed (+6)
2. `flutter test test/features/reader_next/bridge/*downloads*`
   - Result: All tests passed (+5)
3. `flutter test test/features/reader_next/runtime/*authority*`
   - Result: All tests passed (+19)
4. `dart analyze lib/features/reader_next/bridge lib/features/reader_next/preflight lib/pages/downloading_page.dart lib/pages/local_comics_page.dart test/features/reader_next test/pages/downloads_page_m17_2_test.dart`
   - Result: No issues found
5. `git diff --check`
   - Result: clean, no output

## Exit Criteria

- app-level downloads smoke proves flag-off explicit legacy route.
- app-level downloads smoke proves flag-on eligible route remains prepared-only.
- app-level downloads smoke proves blocked rows are terminal and do not fallback.
- kill-switch does not mutate M14/M17 readiness or identity state.
- eligible prepared output still exposes no `ReaderNextOpenRequest`.
- diagnostics are emitted and redacted for all three decision classes.
- downloads executor/navigation wiring remains disabled.
- history/favorites behavior remains unchanged.
