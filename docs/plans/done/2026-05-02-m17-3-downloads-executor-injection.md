# M17.3 Downloads Executor Injection

Goal:

- Convert eligible downloads decision from prepared-only into injected executor callback dispatch.
- Keep downloads page unaware of ReaderNext runtime, presentation screen, and executor implementation.
- Keep actual ReaderNext navigation wiring out of this milestone.

Scope:

- downloads executor injection only
- downloads eligible path only
- no actual ReaderNext navigation executor implementation
- no downloads page ReaderNext runtime import
- no downloads page ReaderNext presentation screen/page import
- no downloads page executor implementation import
- no identity reconstruction
- no fallback after blocked downloads decision
- no history/favorites behavior change

## Hard Rules

1. M17.3 may only add injected executor dispatch for eligible downloads.
2. M17.3 must not add actual ReaderNext navigation implementation for downloads.
3. Downloads page must not import ReaderNext runtime.
4. Downloads page must not import ReaderNext presentation screen/page classes.
5. Downloads page must not import executor implementation.
6. Downloads page must not construct `ReaderNextOpenRequest` directly.
7. Downloads page must not construct `SourceRef` directly.
8. Downloads page must not parse or derive canonical/upstream/chapter IDs.
9. Downloads page may pass only row context into the bridge/controller path.
10. Executor input must be a validated request/result produced by the bridge/controller path.
11. `readerNextEligible` must dispatch injected executor exactly once.
12. `blocked` must dispatch executor zero times and legacy zero times.
13. `legacyExplicit` must call explicit legacy route exactly once and executor zero times.
14. Local/cache/archive/file paths remain storage-only and must not affect route identity.
15. Kill-switch semantics from M17.2 must remain unchanged.
16. History/favorites behavior must remain unchanged.

## Route Behavior

| State                                                     | Expected Decision    | Legacy Callback | Injected Executor | Blocked State    |
| --------------------------------------------------------- | -------------------- | --------------- | ----------------- | ---------------- |
| `reader_next_downloads_enabled=false`                     | `legacyExplicit`     | called once     | not called        | not called       |
| `reader_next_downloads_enabled=true` + downloads eligible | `readerNextEligible` | not called      | called once       | not called       |
| `reader_next_downloads_enabled=true` + downloads blocked  | `blocked`            | not called      | not called        | rendered/emitted |

## Executor Injection Contract

The injected executor may receive only a validated bridge/controller output for an eligible downloads row.

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

The bridge/controller owns request preparation and validation. The downloads page only dispatches based on the controller decision.

## Tasks

| Task ID  | Deliverable                                                                           | Verification              |
| -------- | ------------------------------------------------------------------------------------- | ------------------------- |
| M17.3-T1 | downloads injected executor seam                                                      | controller/widget test    |
| M17.3-T2 | eligible downloads dispatches injected executor exactly once                          | widget/controller test    |
| M17.3-T3 | blocked downloads never reaches executor or legacy fallback                           | widget/controller test    |
| M17.3-T4 | flag off downloads calls explicit legacy only                                         | widget/controller test    |
| M17.3-T5 | eligible executor input is bridge/controller-produced validated output only           | controller test           |
| M17.3-T6 | authority guard: downloads page has no runtime/screen/executor implementation imports | grep-backed test          |
| M17.3-T7 | regression guard: history/favorites unchanged                                         | authority/regression test |

## Acceptance Tests

```dart
testWidgets('eligible downloads dispatches injected executor exactly once', (tester) async {
  // flag on + M14/M17 valid explicit identity
  // expect decision=readerNextEligible
  // expect executor count == 1
  // expect legacy count == 0
});

testWidgets('blocked downloads never reaches executor or legacy fallback', (tester) async {
  // missing/malformed/stale/canonicalLeak SourceRef
  // expect decision=blocked
  // expect executor count == 0
  // expect legacy count == 0
  // expect blocked state
});

testWidgets('flag off downloads calls explicit legacy only', (tester) async {
  // reader_next_downloads_enabled=false
  // expect decision=legacyExplicit
  // expect legacy count == 1
  // expect executor count == 0
});

test('downloads eligible executor input is bridge/controller-produced only', () {
  // expect executor receives validated bridge/controller output
  // expect page does not pass raw canonical/upstream/chapter/path fields
});

test('downloads page remains unaware of executor implementation', () async {
  // grep downloading/local_comics pages
  // expect no ReaderNext runtime import
  // expect no ReaderNext presentation screen/page import
  // expect no executor implementation import
});
```

## Authority Guards

Required guard coverage:

- downloads page remains free of ReaderNext runtime imports.
- downloads page remains free of ReaderNext presentation screen/page imports.
- downloads page remains free of executor implementation imports.
- downloads page does not construct `ReaderNextOpenRequest`.
- downloads page does not construct `SourceRef`.
- downloads page does not parse or derive canonical/upstream/chapter IDs.
- blocked branch does not call explicit legacy route.
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
- eligible downloads dispatch uses injected callback only.
- blocked downloads do not reach executor or legacy route.
- history/favorites remain unchanged.

## Verification Commands

```bash
flutter test test/pages/downloads_page_m17_3_test.dart
flutter test test/features/reader_next/bridge/*downloads*
flutter test test/features/reader_next/runtime/*authority*
dart analyze lib/features/reader_next/bridge lib/features/reader_next/preflight lib/pages/downloading_page.dart lib/pages/local_comics_page.dart test/features/reader_next test/pages/downloads_page_m17_3_test.dart
git diff --check
```

## M17.3 Closeout Evidence

M17.3 completed as downloads injected-executor dispatch only.

Verified:

- eligible downloads dispatch injected executor exactly once
- blocked downloads dispatch executor zero times and legacy zero times
- flag-off downloads dispatch explicit legacy route only
- downloads pages remain free of ReaderNext runtime/presentation/executor implementation imports
- downloads pages do not construct `ReaderNextOpenRequest` or `SourceRef`
- actual ReaderNext navigation wiring was not introduced
- history/favorites behavior remains unchanged

Final verification:

1. `flutter test test/pages/downloads_page_m17_3_test.dart`
   - Result: All tests passed (+5)
2. `flutter test test/features/reader_next/bridge/*downloads*`
   - Result: All tests passed (+5)
3. `flutter test test/features/reader_next/runtime/*authority*`
   - Result: All tests passed (+21)
4. `dart analyze lib/features/reader_next/bridge lib/features/reader_next/preflight lib/pages/downloading_page.dart lib/pages/local_comics_page.dart test/features/reader_next test/pages/downloads_page_m17_3_test.dart`
   - Result: No issues found
5. `git diff --check`
   - Result: clean, no output

## Exit Criteria

- eligible downloads dispatches injected executor exactly once.
- blocked downloads dispatches executor zero times and legacy zero times.
- flag-off downloads dispatches explicit legacy route only.
- downloads page remains free of ReaderNext runtime/screen/executor implementation imports.
- downloads page does not construct `ReaderNextOpenRequest` or `SourceRef`.
- executor input is bridge/controller-produced and validated.
- actual ReaderNext navigation wiring is not introduced.
- history/favorites behavior remains unchanged.
