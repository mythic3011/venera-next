# M16.1 Favorites ReaderNext Route Cutover Wiring

Goal:

- wire favorites as the next ReaderNext entrypoint using M14 + M16 authority only
- keep page layer free from identity building and ReaderNext internals

Scope:

- favorites controller-first wiring
- page passes row context only
- second segment wires row-context -> controller decision only
- injected executor/adaptor pattern only
- blocked terminal only
- downloads remain disabled
- no actual favorites ReaderNext navigation in the second segment
- no executor invocation in the second segment
- third segment enables injected executor dispatch for eligible favorites only
- third segment still does not allow favorites page to import ReaderNext runtime/screen/executor implementation

## Hard Rules

1. Only favorites entrypoint may be wired in this milestone.
2. Route authority must consume only M14 readiness artifact + M16 favorites preflight decision.
3. `folderName` is required at open time.
4. Favorites page must not build `SourceRef` or `ReaderNextOpenRequest`.
5. Favorites page must not parse `canonicalComicId` / `upstreamComicRefId`.
6. Favorites page must not import ReaderNext runtime/screen.
7. Blocked decisions are terminal and must not fallback to legacy.
8. Downloads route remains disabled.
9. Executor must be injected callback/adaptor; page must not import executor implementation.

10. In the second segment, favorites page may call the controller but must not call ReaderNext executor/navigation yet.
11. In the second segment, `readerNextEligible` means prepared/diagnostic only, not navigation.
12. Favorites page may pass only row context fields: `folderName`, `recordId`, and `sourceKey`.
13. Favorites page must not derive or validate SourceRef identity itself.
14. `legacyExplicit` may call only the explicit legacy route.
15. `blocked` must render/emit a blocked state and must not call legacy or executor.
16. In the third segment, `readerNextEligible` may call only an injected executor callback/adaptor.
17. In the third segment, `readerNextEligible` must call the injected executor exactly once.
18. In the third segment, `blocked` must call executor zero times and legacy zero times.
19. In the third segment, `legacyExplicit` must call legacy exactly once and executor zero times.
20. Executor input must be a validated `ReaderNextOpenRequest` produced by the bridge/controller path.
21. Favorites page must not import executor implementation.
22. Favorites page must not import ReaderNext presentation screen/page classes.
23. Downloads remain disabled during third-segment executor injection.

## Tasks

| Task ID   | Deliverable                                                                                    | Verification           |
| --------- | ---------------------------------------------------------------------------------------------- | ---------------------- |
| M16.1-T1  | favorites cutover controller consumes M14 + M16 preflight                                      | controller test        |
| M16.1-T2  | favorites route decision diagnostic contract                                                   | diagnostic test        |
| M16.1-T3  | blocked terminal policy (no legacy fallback)                                                   | controller test        |
| M16.1-T4  | injected favorites executor contract (callback/adaptor)                                        | controller test        |
| M16.1-T5  | authority guard: favorites page does not build identity or SourceRef                           | grep-backed test       |
| M16.1-T6  | authority guard: downloads still disabled                                                      | grep-backed test       |
| M16.1-T7  | favorites page passes folder-scoped row context to controller                                  | widget/page test       |
| M16.1-T8  | favorites eligible path is prepared/diagnostic only before executor wiring                     | widget/page test       |
| M16.1-T9  | favorites blocked path renders blocked state without legacy fallback                           | widget/page test       |
| M16.1-T10 | authority guard precision pass for favorites/download false positives                          | grep-backed test       |
| M16.1-T11 | eligible favorites dispatches injected executor exactly once                                   | widget/controller test |
| M16.1-T12 | blocked favorites never reaches executor                                                       | widget/controller test |
| M16.1-T13 | legacyExplicit favorites calls only explicit legacy route                                      | widget/controller test |
| M16.1-T14 | authority guard: favorites page remains free of runtime/screen/executor implementation imports | grep-backed test       |

## Acceptance Tests

```dart
test('favorites controller uses M14 + M16 preflight only', () {
  // assert decision path depends on readiness artifact + favorites preflight result
});

test('favorites blocked decision never calls legacy fallback', () {
  // blocked => no legacy callback and no executor callback
});

test('favorites page does not build identity or SourceRef', () async {
  // grep favorites page files
  // expect no SourceRef.
  // expect no ReaderNextOpenRequest(
  // expect no canonicalComicId / upstreamComicRefId parsing
});

testWidgets('favorites page passes folder-scoped row context to controller', (tester) async {
  // folderName=A, recordId=646922, sourceKey=nhentai
  // expect controller received all three fields
  // expect page did not construct SourceRef or ReaderNextOpenRequest
});

testWidgets('favorites eligible path is prepared only before executor wiring', (tester) async {
  // flag on + M14/M16 eligible
  // expect decision=readerNextEligible
  // expect no legacy callback
  // expect no executor callback
  // expect prepared diagnostic/state only
});

testWidgets('favorites blocked path does not fallback to legacy', (tester) async {
  // missing/stale folder-scoped identity
  // expect blocked state
  // expect legacy callback count == 0
  // expect executor callback count == 0
});

testWidgets('eligible favorites dispatches injected executor exactly once', (tester) async {
  // flag on + M14/M16 eligible
  // expect decision=readerNextEligible
  // expect injected executor callback count == 1
  // expect legacy callback count == 0
});

testWidgets('blocked favorites never reaches executor', (tester) async {
  // flag on + blocked favorite row
  // expect decision=blocked
  // expect injected executor callback count == 0
  // expect legacy callback count == 0
});

testWidgets('legacyExplicit favorites calls only explicit legacy route', (tester) async {
  // favorites flag off
  // expect decision=legacyExplicit
  // expect legacy callback count == 1
  // expect injected executor callback count == 0
});

test('favorites page remains unaware of ReaderNext executor implementation', () async {
  // grep favorites page files
  // expect no ReaderNext runtime import
  // expect no ReaderNext presentation screen/page import
  // expect no executor implementation import
});
```

## Second Segment Route Behavior

| State                        | Expected Decision    | Legacy Callback | ReaderNext Executor | Blocked/Prepared State   |
| ---------------------------- | -------------------- | --------------- | ------------------- | ------------------------ |
| favorites flag off           | `legacyExplicit`     | called once     | not called          | not called               |
| favorites flag on + eligible | `readerNextEligible` | not called      | not called          | prepared/diagnostic only |
| favorites flag on + blocked  | `blocked`            | not called      | not called          | blocked state            |

The second segment intentionally stops before actual ReaderNext executor/navigation wiring. Executor wiring belongs to a later M16.1 segment after page-level row-context dispatch is verified.

## Authority Guard Precision Pass

M16.1-T10 narrows authority guards to open-reader identity construction and ReaderNext route wiring.

The guard must reject these patterns in favorites page code:

- `SourceRef.` construction
- `ReaderNextOpenRequest(` construction
- `upstreamComicRefId` parsing or assignment
- `fromLegacyRemote` identity rebuilding
- `routeFavorites*ReaderNext` direct route wiring
- `open*ReaderNext` direct navigation wiring

The guard must not fail on unrelated download/status helpers such as `canonicalComicIdForStatus(...)` when they are not ReaderNext route wiring.

Suggested precision guard:

```bash
rg -n "SourceRef\\.|ReaderNextOpenRequest\\(|upstreamComicRefId|fromLegacyRemote|routeFavorites.*ReaderNext|open.*ReaderNext" \
  lib/pages/favorites lib/pages/favorites_page.dart \
  -g '!*.g.dart'
```

Expected:

- no favorites page identity construction
- no favorites page ReaderNext request construction
- no favorites page upstream ID parsing
- no direct favorites ReaderNext navigation wiring
- no false-positive failure from unrelated download status helpers

## M16.1 Second Segment Closeout Evidence

M16.1 second segment completed as row-context handoff plus controller decision verification only.

Verified:

- favorites page passes folder-scoped row context to controller
- favorites eligible path remains prepared/diagnostic only
- favorites blocked path does not fallback to legacy
- no favorites ReaderNext executor/navigation wiring was introduced
- favorites page does not construct `SourceRef` or `ReaderNextOpenRequest`
- authority guard targets open-reader identity construction instead of unrelated download status helpers

Final verification:

1. `flutter test test/pages/favorites_page_m16_1_test.dart`
   - Result: All tests passed (+2)
2. `flutter test test/features/reader_next/bridge/favorites_route_cutover_controller_test.dart`
   - Result: All tests passed (+3)
3. `flutter test test/features/reader_next/runtime/*authority*`
   - Result: All tests passed (+17)
4. `dart analyze lib/features/reader_next/bridge lib/pages/favorites test/features/reader_next test/pages/favorites_page_m16_1_test.dart`
   - Result: No issues found
5. `git diff --check`
   - Result: clean, no output

## M16.1 Third Segment - Favorites Executor Injection

Goal:

- Convert eligible favorites decision from prepared/diagnostic only into injected executor callback dispatch.
- Keep favorites page unaware of ReaderNext presentation/runtime/executor implementation.
- Keep downloads disabled.

Scope:

- executor injection only
- favorites eligible path only
- no downloads route wiring
- no identity reconstruction
- no fallback after blocked favorites decision
- no direct ReaderNext navigation wiring inside favorites page

### Third Segment Route Behavior

| State                        | Expected Decision    | Legacy Callback | Injected Executor | Blocked/Prepared State |
| ---------------------------- | -------------------- | --------------- | ----------------- | ---------------------- |
| favorites flag off           | `legacyExplicit`     | called once     | not called        | not called             |
| favorites flag on + eligible | `readerNextEligible` | not called      | called once       | not called             |
| favorites flag on + blocked  | `blocked`            | not called      | not called        | blocked state          |

### Executor Injection Contract

The injected executor may receive only:

- a validated `ReaderNextOpenRequest` produced by the bridge/controller path

The favorites page must not pass:

- raw `folderName`
- raw `recordId`
- raw `sourceKey`
- raw `canonicalComicId`
- raw `upstreamComicRefId`
- raw `chapterRefId`
- M12 report data
- M13 apply report data
- M14 readiness artifact data
- M16 preflight internals

The favorites page may only pass row context to the controller and dispatch on the controller result.

### Third Segment Authority Guards

Required guard coverage:

- favorites page has no ReaderNext runtime imports.
- favorites page has no ReaderNext presentation screen/page imports.
- favorites page has no executor implementation imports.
- favorites page does not construct `ReaderNextOpenRequest`.
- favorites page does not construct `SourceRef`.
- downloads still do not reference ReaderNext bridge/controller/executor classes.

Suggested guard:

```bash
rg -n "features/reader_next/(runtime|presentation)|ReaderNext.*Page|ReaderNext.*Screen|HistoryReaderNextNavigationExecutor|FavoritesReaderNextNavigationExecutor" \
  lib/pages/favorites lib/pages/favorites_page.dart \
  -g '!*.g.dart'

rg -n "SourceRef\\.|ReaderNextOpenRequest\\(|upstreamComicRefId|fromLegacyRemote|routeFavorites.*ReaderNext|open.*ReaderNext" \
  lib/pages/favorites lib/pages/favorites_page.dart \
  -g '!*.g.dart'
```

Expected:

- no runtime/screen/executor implementation imports in favorites page code.
- no identity construction in favorites page code.
- eligible favorites dispatch uses injected callback only.
- blocked favorites do not reach executor or legacy route.

## M16.1 Third Segment Closeout Evidence

M16.1 third segment completed as favorites injected-executor dispatch only.

Verified:

- eligible favorites dispatch injected executor exactly once
- blocked favorites dispatch executor zero times and legacy zero times
- `legacyExplicit` favorites dispatch explicit legacy route only
- favorites page does not construct `SourceRef`
- favorites page does not construct `ReaderNextOpenRequest`
- favorites page does not import ReaderNext runtime/screen/executor implementation
- bridge/controller owns ReaderNext request construction
- downloads remain disabled
- `reader_next_favorites_enabled` is added as route-selection flag only

Final verification:

1. `flutter test test/features/reader_next/bridge/favorites_route_cutover_controller_test.dart`
   - Result: All tests passed (+6)
2. `flutter test test/pages/favorites_page_m16_1_test.dart`
   - Result: All tests passed (+3)
3. `flutter test test/features/reader_next/runtime/*authority*`
   - Result: All tests passed (+17)
4. `dart analyze lib/features/reader_next/bridge lib/pages/favorites lib/foundation/appdata.dart lib/pages/settings/settings_schema.dart test/features/reader_next test/pages/favorites_page_m16_1_test.dart`
   - Result: No issues found
5. `git diff --check`
   - Result: clean, no output

## Verification

```bash
flutter test test/pages/favorites_page_m16_1_test.dart
flutter test test/features/reader_next/bridge/favorites_route_cutover_controller_test.dart
flutter test test/features/reader_next/runtime/*authority*
dart analyze lib/features/reader_next/bridge lib/pages/favorites lib/foundation/appdata.dart lib/pages/settings/settings_schema.dart test/features/reader_next test/pages/favorites_page_m16_1_test.dart
git diff --check
```

## Next Stage: M16.2 Favorites ReaderNext Runtime Smoke + Kill-Switch Verification

Goal:

- Verify the actual favorites ReaderNext cutover path behaves safely in app-level smoke tests.
- Prove kill-switch rollback works without touching M14/M16 readiness or identity state.
- Keep downloads disabled.

Scope:

- smoke/integration tests only
- favorites entrypoint only
- no downloads route wiring
- no identity reconstruction
- no fallback after blocked favorites decision
- no new ReaderNext entrypoints

### Hard Rules

1. `reader_next_favorites_enabled=false` returns favorites opens to explicit legacy route.
2. Kill-switch affects route selection only.
3. Kill-switch must not mutate M14 readiness artifact, M16 preflight state, SourceRef snapshots, favorites rows, history rows, or downloads rows.
4. `reader_next_favorites_enabled=true` must still pass M14 readiness + M16 folder-scoped preflight.
5. Blocked favorites rows are terminal: no legacy fallback and no executor call.
6. Favorites row identity remains `folderName + recordId + sourceKey`.
7. Duplicate favorite rows across folders must remain independently decided.
8. Diagnostics must include `folderName`, schema version, current validation code, route decision, and redacted record id.
9. Diagnostics must not expose raw canonical IDs, upstream IDs, chapter IDs, cookies, headers, tokens, or full URLs.
10. Downloads remain disabled even if readiness is true.
11. Favorites page must remain bridge/controller-only and must not import ReaderNext runtime/screen/executor implementation.
12. M16.2 must not change M16/M16.1 identity semantics.

### Tasks

| Task ID  | Deliverable                                                                                                                     | Verification            |
| -------- | ------------------------------------------------------------------------------------------------------------------------------- | ----------------------- |
| M16.2-T1 | app-level smoke: favorites flag off uses explicit legacy route                                                                  | widget/integration test |
| M16.2-T2 | app-level smoke: favorites flag on + eligible dispatches injected executor once                                                 | widget/integration test |
| M16.2-T3 | app-level smoke: favorites flag on + blocked renders blocked state and does not fallback                                        | widget/integration test |
| M16.2-T4 | kill-switch test: disabling `reader_next_favorites_enabled` stops ReaderNext attempts without mutating readiness/identity state | controller/widget test  |
| M16.2-T5 | duplicate-folder smoke: same favorite id in different folders remains independently decided                                     | fixture/widget test     |
| M16.2-T6 | diagnostic smoke: legacyExplicit, readerNextEligible, and blocked decisions emit redacted packets                               | diagnostic test         |
| M16.2-T7 | authority guard: downloads still have no ReaderNext route/executor wiring                                                       | grep-backed test        |

### Smoke Decision Matrix

| State                                                    | Expected Decision            | Legacy Callback | Injected Executor | Blocked Callback |
| -------------------------------------------------------- | ---------------------------- | --------------- | ----------------- | ---------------- |
| `reader_next_favorites_enabled=false`                    | `legacyExplicit`             | called once     | not called        | not called       |
| `reader_next_favorites_enabled=true` + favorite eligible | `readerNextEligible`         | not called      | called once       | not called       |
| `reader_next_favorites_enabled=true` + favorite blocked  | `blocked`                    | not called      | not called        | called once      |
| duplicate rows: folder A eligible, folder B blocked      | independent decisions        | per row         | per row           | per row          |
| downloads readiness true                                 | ignored by favorites cutover | unchanged       | not wired         | unchanged        |

### Kill-Switch Contract

Kill-switch means:

- set `reader_next_favorites_enabled=false`
- favorites open returns to explicit legacy route
- ReaderNext bridge/executor is not called for favorites
- M14 readiness artifact is not changed
- M16 favorites preflight state is not changed
- SourceRef snapshots are not changed
- favorites/history/download rows are not changed
- downloads remain disabled

Kill-switch does not mean:

- fallback after a blocked ReaderNext decision
- accepting malformed SourceRef
- bypassing current-row validation
- changing M14 readiness decisions
- changing M16 folder-scoped identity rules
- enabling or disabling other entrypoints

### Required Tests

```dart
testWidgets('favorites smoke: flag off uses explicit legacy route', (tester) async {
  // reader_next_favorites_enabled=false
  // expect routeDecision=legacyExplicit
  // expect legacy callback count == 1
  // expect injected executor count == 0
});

testWidgets('favorites smoke: flag on eligible dispatches executor once', (tester) async {
  // valid folder-scoped row
  // reader_next_favorites_enabled=true
  // M14 favoritesReady=true
  // M16 preflight valid
  // expect routeDecision=readerNextEligible
  // expect injected executor count == 1
  // expect legacy callback count == 0
});

testWidgets('favorites smoke: blocked row does not fallback', (tester) async {
  // missing folderName / stale fingerprint / malformed SourceRef
  // expect routeDecision=blocked
  // expect blocked state
  // expect legacy callback count == 0
  // expect injected executor count == 0
});

test('favorites kill-switch does not mutate readiness or identity state', () {
  // capture M14/M16 decision inputs
  // toggle reader_next_favorites_enabled=false
  // assert captured readiness/preflight/SourceRef state unchanged
});

testWidgets('duplicate favorites in different folders remain independent', (tester) async {
  // same recordId/sourceKey
  // folder A eligible
  // folder B blocked
  // expect A executor once
  // expect B blocked only
});

test('favorites diagnostics are redacted for all route decisions', () {
  // emit legacyExplicit, readerNextEligible, blocked packets
  // expect folderName present
  // expect raw recordId/canonical/upstream/chapter ids absent
});
```

### Authority Guards

Required guard coverage:

- favorites page remains free of ReaderNext runtime imports.
- favorites page remains free of ReaderNext presentation screen/page imports.
- favorites page remains free of executor implementation imports.
- favorites page does not construct `ReaderNextOpenRequest`.
- favorites page does not construct `SourceRef`.
- favorites page does not parse or derive canonical/upstream/chapter IDs.
- downloads still do not reference ReaderNext bridge/controller/executor classes.
- no blocked branch calls legacy route.
- no diagnostics expose raw canonical/upstream/chapter IDs.

Suggested guard commands:

```bash
rg -n "features/reader_next/(runtime|presentation)|ReaderNext.*Page|ReaderNext.*Screen|FavoritesReaderNextNavigationExecutor" \
  lib/pages/favorites lib/pages/favorites_page.dart \
  -g '!*.g.dart'

rg -n "SourceRef\\.|ReaderNextOpenRequest\\(|upstreamComicRefId|canonicalComicId|chapterRefId|fromLegacyRemote" \
  lib/pages/favorites lib/pages/favorites_page.dart \
  -g '!*.g.dart'

rg -n "ReaderNextOpenBridge|OpenReaderController|ReaderNextHistoryOpenExecutor|ReaderNextNavigationExecutor|FavoritesReaderNext" \
  lib/pages/downloads lib/pages/local_comics_page.dart \
  -g '!*.g.dart'

rg -n "blocked[\\s\\S]{0,240}openLegacy|openLegacy[\\s\\S]{0,240}blocked" \
  lib/features/reader_next/bridge lib/pages/favorites test/features/reader_next test/pages \
  -g '!*.g.dart'
```

Expected:

- no favorites page identity construction.
- no favorites page ReaderNext runtime/screen/executor implementation imports.
- no downloads ReaderNext route/executor wiring.
- no blocked-to-legacy branch.
- no raw identity leakage in diagnostics.

### Verification Commands

```bash
flutter test test/pages/favorites_page_m16_2_test.dart
flutter test test/features/reader_next/bridge/favorites_route_cutover_controller_test.dart
flutter test test/features/reader_next/runtime/*authority*
dart analyze lib/features/reader_next/bridge lib/pages/favorites lib/foundation/appdata.dart lib/pages/settings/settings_schema.dart test/features/reader_next test/pages/favorites_page_m16_2_test.dart
git diff --check
```

### M16.2 Closeout Evidence

M16.2 completed as favorites runtime smoke + kill-switch verification only.

Verified:

- flag off favorites open uses explicit legacy route with `legacyExplicit`
- flag on + eligible favorites open dispatches injected executor exactly once
- flag on + blocked favorites open is terminal: no legacy fallback and no executor call
- kill-switch does not mutate M14 readiness, M16 preflight, SourceRef, favorites, history, or downloads state
- duplicate favorite rows across folders remain independently decided
- diagnostics cover `legacyExplicit`, `readerNextEligible`, and `blocked`
- diagnostics are redacted by default
- downloads remain without ReaderNext route/executor wiring
- favorites page remains bridge/controller-only and does not import ReaderNext runtime/screen/executor implementation

Final verification:

1. `flutter test test/pages/favorites_page_m16_2_test.dart`
   - Result: All tests passed (+6)
2. `flutter test test/features/reader_next/bridge/favorites_route_cutover_controller_test.dart`
   - Result: All tests passed (+6)
3. `flutter test test/features/reader_next/runtime/*authority*`
   - Result: All tests passed (+17)
4. `dart analyze lib/features/reader_next/bridge lib/pages/favorites lib/foundation/appdata.dart lib/pages/settings/settings_schema.dart test/features/reader_next test/pages/favorites_page_m16_2_test.dart`
   - Result: No issues found
5. `git diff --check`
   - Result: clean, no output

### M16.2 Exit Criteria

- app-level favorites smoke proves flag-off explicit legacy route.
- app-level favorites smoke proves flag-on eligible route dispatches injected executor exactly once.
- app-level favorites smoke proves blocked rows are terminal and do not fallback.
- kill-switch does not mutate M14/M16 readiness or identity state.
- duplicate favorite rows across folders remain independently decided.
- diagnostics are emitted and redacted for all three decision classes.
- downloads remain disabled even if readiness values are true.
