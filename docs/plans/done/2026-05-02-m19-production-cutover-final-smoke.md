# M19 Production Cutover Final Smoke / Rollback Matrix

Goal:

- Verify the full ReaderNext production cutover path across history, favorites, and downloads.
- Prove rollback/kill-switch behavior for every enabled entrypoint.
- Confirm legacy fallback is available only through explicit flag-off route selection, never after a ReaderNext blocked decision.
- Close the ReaderNext cutover lane without adding new route semantics.

Scope:

- final smoke / rollback verification only
- no new ReaderNext entrypoints
- no new identity model
- no new fallback behavior
- no SourceRef reconstruction
- no ReaderNext request construction in production pages
- no M14/M16/M17 readiness mutation
- no importer/backfill changes
- no UI redesign

## Hard Rules

1. M19 must not add new route semantics.
2. M19 must not add new identity derivation logic.
3. M19 must not change M14 readiness semantics.
4. M19 must not change M16 favorites folder-scoped identity semantics.
5. M19 must not change M17 downloads explicit-identity semantics.
6. Production pages must not construct `ReaderNextOpenRequest`.
7. Production pages must not construct `SourceRef`.
8. Production pages must not import ReaderNext runtime directly.
9. Production pages must not import ReaderNext presentation screen/page classes directly.
10. Production pages must not import approved navigation executor implementation directly.
11. Approved executor remains the only final ReaderNext navigation path.
12. Feature flags control route selection only.
13. Feature flags must not relax validation.
14. Flag-off route selection may use explicit legacy route.
15. ReaderNext blocked decision must be terminal: no legacy fallback and no approved executor call.
16. Kill-switch must not mutate readiness, identity, SourceRef snapshots, or route authority artifacts.
17. Diagnostics must remain redacted by default.
18. Diagnostics must not expose raw canonical IDs, upstream IDs, chapter IDs, local paths, cache paths, archive paths, filenames, URLs, cookies, headers, or tokens.
19. History, favorites, and downloads must keep independent kill-switches.
20. Route authority must remain controller-owned, not page-owned.

## Entrypoint Matrix

| Entrypoint | Route Flag                      | Identity Authority                              | Eligible Behavior      | Blocked Behavior | Flag-Off Behavior |
| ---------- | ------------------------------- | ----------------------------------------------- | ---------------------- | ---------------- | ----------------- |
| history    | `reader_next_history_enabled`   | M14 readiness + current-row validation          | approved executor once | blocked terminal | explicit legacy   |
| favorites  | `reader_next_favorites_enabled` | M14 readiness + M16 folder-scoped preflight     | approved executor once | blocked terminal | explicit legacy   |
| downloads  | `reader_next_downloads_enabled` | M14 readiness + M17 explicit-identity preflight | approved executor once | blocked terminal | explicit legacy   |

## Rollback Contract

Rollback means:

- disabling the entrypoint-specific flag
- route selection returns to explicit legacy route for that entrypoint
- approved executor is not called for that entrypoint
- ReaderNext blocked-state semantics remain unchanged when the flag is on
- readiness artifacts are not mutated
- SourceRef snapshots are not mutated
- history/favorites/downloads rows are not mutated
- importer/backfill state is not mutated

Rollback does not mean:

- fallback after a blocked ReaderNext decision
- accepting malformed SourceRef
- bypassing M14/M16/M17 validation
- changing identity fingerprints
- changing candidate IDs
- changing route authority artifacts
- enabling/disabling another entrypoint

## Tasks

| Task ID | Deliverable                                                                                         | Verification            |
| ------- | --------------------------------------------------------------------------------------------------- | ----------------------- |
| M19-T1  | final smoke matrix for history/favorites/downloads flag-off behavior                                | widget/integration test |
| M19-T2  | final smoke matrix for eligible behavior dispatching approved executor once                         | widget/integration test |
| M19-T3  | final smoke matrix for blocked behavior being terminal                                              | widget/integration test |
| M19-T4  | rollback matrix proving independent kill-switches                                                   | controller/widget test  |
| M19-T5  | diagnostics matrix for all entrypoints and decisions                                                | diagnostic test         |
| M19-T6  | authority guard: pages remain free of request/source/runtime/screen/executor implementation imports | grep-backed test        |
| M19-T7  | authority guard: no blocked-to-legacy or blocked-to-executor branch exists                          | grep-backed test        |
| M19-T8  | regression guard: M14/M16/M17 route authority semantics unchanged                                   | regression test         |
| M19-T9  | final verification command bundle                                                                   | manual/test report      |

## Required Smoke Tests

```dart
testWidgets('M19 flag-off matrix uses explicit legacy route only', (tester) async {
  // history flag off -> legacy once, approved executor zero
  // favorites flag off -> legacy once, approved executor zero
  // downloads flag off -> legacy once, approved executor zero
});

testWidgets('M19 eligible matrix dispatches approved executor exactly once', (tester) async {
  // history eligible -> approved executor once, legacy zero
  // favorites eligible -> approved executor once, legacy zero
  // downloads eligible -> approved executor once, legacy zero
});

testWidgets('M19 blocked matrix is terminal for every entrypoint', (tester) async {
  // history blocked -> blocked state, approved executor zero, legacy zero
  // favorites blocked -> blocked state, approved executor zero, legacy zero
  // downloads blocked -> blocked state, approved executor zero, legacy zero
});

test('M19 rollback matrix keeps entrypoint kill-switches independent', () {
  // disabling history flag must not disable favorites/downloads
  // disabling favorites flag must not disable history/downloads
  // disabling downloads flag must not disable history/favorites
});

test('M19 rollback does not mutate readiness or identity state', () {
  // capture M14 readiness artifact
  // capture M16 favorites preflight state
  // capture M17 downloads preflight state
  // capture SourceRef snapshots
  // toggle each flag off
  // assert captured state unchanged
});

test('M19 diagnostics are redacted for all entrypoints and decisions', () {
  // emit legacyExplicit, readerNextEligible, blocked for history/favorites/downloads
  // expect raw canonical/upstream/chapter/path/url/token/header values absent
  // expect redacted/hash fields only
});

test('M19 pages do not own route authority or identity construction', () async {
  // grep production pages
  // expect no ReaderNextOpenRequest(
  // expect no SourceRef.
  // expect no ReaderNext runtime/screen/executor implementation imports
  // expect no raw M14/M16/M17 artifact consumption
});
```

## Authority Guards

Required guard coverage:

- production pages do not construct `ReaderNextOpenRequest`.
- production pages do not construct `SourceRef`.
- production pages do not import ReaderNext runtime.
- production pages do not import ReaderNext presentation screen/page classes.
- production pages do not import approved executor implementation directly.
- production pages do not parse canonical/upstream/chapter IDs.
- production pages do not consume M14/M16/M17 raw artifacts as route authority.
- blocked branches do not call legacy fallback.
- blocked branches do not call approved executor.
- diagnostics do not expose raw identity/path/network-sensitive values.

Suggested guard commands:

```bash
rg -n "ReaderNextOpenRequest\\(|SourceRef\\.|upstreamComicRefId|chapterRefId|fromLegacyRemote|canonicalComicId" \
  lib/pages/history_page.dart lib/pages/favorites lib/pages/downloading_page.dart lib/pages/local_comics_page.dart \
  -g '!*.g.dart'

rg -n "features/reader_next/(runtime|presentation)|ReaderNext.*Page|ReaderNext.*Screen|ApprovedReaderNextNavigationExecutor|ReaderNextNavigationExecutor" \
  lib/pages/history_page.dart lib/pages/favorites lib/pages/downloading_page.dart lib/pages/local_comics_page.dart \
  -g '!*.g.dart'

rg -n "ReadinessArtifact|history_favorites_route_readiness_gate|favorites_route_cutover_preflight|downloads_route_readiness_preflight|BackfillApplyPlan|IdentityCoverageReport" \
  lib/pages/history_page.dart lib/pages/favorites lib/pages/downloading_page.dart lib/pages/local_comics_page.dart \
  -g '!*.g.dart'

rg -n "blocked[\\s\\S]{0,240}(openLegacy|approvedExecutor|navigationExecutor)|(?:openLegacy|approvedExecutor|navigationExecutor)[\\s\\S]{0,240}blocked" \
  lib/features/reader_next/bridge lib/pages/history_page.dart lib/pages/favorites lib/pages/downloading_page.dart lib/pages/local_comics_page.dart test/features/reader_next test/pages \
  -g '!*.g.dart'
```

Expected:

- no page-level request or SourceRef construction.
- no page-level ReaderNext runtime/screen/executor implementation imports.
- no page-level raw artifact authority usage.
- no blocked-to-legacy branch.
- no blocked-to-approved-executor branch.

## Verification Commands

```bash
flutter test test/features/reader_next/presentation/*navigation_executor*
flutter test test/pages/history_page_m15_test.dart
flutter test test/pages/favorites_page_m16_2_test.dart
flutter test test/pages/downloads_page_m17_4_test.dart
flutter test test/pages/m19_production_cutover_final_smoke_test.dart
flutter test test/features/reader_next/runtime/*authority*
dart analyze lib/features/reader_next/bridge lib/features/reader_next/presentation lib/pages/history_page.dart lib/pages/favorites lib/pages/downloading_page.dart lib/pages/local_comics_page.dart test/features/reader_next test/pages
git diff --check
```

## Exit Criteria

- flag-off behavior uses explicit legacy route for history, favorites, and downloads.
- eligible behavior dispatches approved executor exactly once for history, favorites, and downloads.
- blocked behavior is terminal for history, favorites, and downloads.
- rollback/kill-switches are independent per entrypoint.
- rollback does not mutate M14/M16/M17 readiness or identity state.
- pages remain free of ReaderNext request/source/runtime/screen/executor implementation ownership.
- diagnostics are redacted by default.
- M14/M16/M17 route authority semantics remain unchanged.
- no new route semantics were introduced.

## M19 Closeout Evidence

M19 implementation completed as smoke/rollback verification lane only.

### Final Verification

1. `flutter test test/features/reader_next/presentation/*navigation_executor*`  
   Result: All tests passed (`+2`).
2. `flutter test test/pages/history_page_m15_test.dart`  
   Result: All tests passed (`+2`).
3. `flutter test test/pages/favorites_page_m16_2_test.dart`  
   Result: All tests passed (`+6`).
4. `flutter test test/pages/downloads_page_m17_4_test.dart`  
   Result: All tests passed (`+6`).
5. `flutter test test/pages/m19_production_cutover_final_smoke_test.dart`  
   Result: All tests passed (`+7`).
6. `flutter test test/features/reader_next/runtime/*authority*`  
   Result: All tests passed (`+24`).
7. `dart analyze lib/features/reader_next/bridge lib/features/reader_next/presentation lib/pages/history_page.dart lib/pages/favorites lib/pages/downloading_page.dart lib/pages/local_comics_page.dart test/features/reader_next test/pages`  
   Result: No issues found.
8. `git diff --check`  
   Result: clean, no output.

### Authority Confirmed

- page layer did not gain request/source construction ownership
- blocked decisions remained terminal (no blocked-to-legacy fallback, no blocked-to-executor)
- approved executor remained the only ReaderNext navigation execution path
- entrypoint kill-switch decisions remained independent
- diagnostics remained redacted
- no M14/M16/M17 authority regression introduced by M19

Note:

- `ReadinessArtifact` may appear in approved favorites page/controller handoff tests only as an injected test fixture or bridge-facing input.
- Production pages must not inspect raw readiness artifact internals or use M14/M16/M17 artifacts as independent route authority.
