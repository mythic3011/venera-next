# M18 Approved ReaderNext Navigation Executor Consolidation

Goal:

- Consolidate history, favorites, and downloads injected executor paths behind one approved ReaderNext navigation executor.
- Keep production pages bridge/controller-only.
- Preserve all existing M15/M16/M17 validation, blocked, diagnostic, and kill-switch semantics.

Scope:

- approved navigation executor consolidation only
- no new entrypoints
- no identity reconstruction
- no SourceRef reconstruction in pages
- no route fallback after blocked decision
- no feature-flag semantics change
- no M14/M16/M17 readiness mutation
- no history/favorites/downloads behavior broadening

## Hard Rules

1. Only the approved executor may import ReaderNext presentation screen/page classes.
2. Production pages must not import ReaderNext presentation screen/page classes directly.
3. Production pages must not import ReaderNext runtime directly.
4. Production pages must not construct `ReaderNextOpenRequest`.
5. Production pages must not construct `SourceRef`.
6. Approved executor accepts only validated `ReaderNextOpenRequest` from bridge/controller output.
7. Approved executor must not accept raw `recordId`, `sourceKey`, `folderName`, `downloadSessionId`, local path, cache path, archive path, filename, canonical ID, upstream ID, or chapter ID.
8. Blocked decisions must never call approved executor.
9. `legacyExplicit` decisions must never call approved executor.
10. Feature flags control route selection only and must not bypass validation.
11. History, favorites, and downloads keep independent kill-switches.
12. No fallback after ReaderNext blocked decision.
13. M18 must not change M14 readiness semantics.
14. M18 must not change M16 favorites folder-scoped identity semantics.
15. M18 must not change M17 downloads explicit-identity semantics.
16. Diagnostics remain redacted by default.
17. Approved executor must not log raw canonical/upstream/chapter IDs, local paths, cache paths, archive paths, filenames, URLs, cookies, headers, or tokens.

## Existing Entrypoint Contracts

M18 consumes the already-validated executor seams from previous milestones.

| Entrypoint | Current Stage                      | M18 Expected Behavior                                              |
| ---------- | ---------------------------------- | ------------------------------------------------------------------ |
| history    | M15.3 smoke + kill-switch verified | eligible path may dispatch approved executor through injected seam |
| favorites  | M16.2 smoke + kill-switch verified | eligible path may dispatch approved executor through injected seam |
| downloads  | M17.4 smoke + kill-switch verified | eligible path may dispatch approved executor through injected seam |

M18 must not create a new route authority source. Existing controllers remain the authority for decision-making.

## Approved Executor Contract

The approved executor may receive only:

- `ReaderNextOpenRequest`

The approved executor must not receive:

- raw `recordId`
- raw `sourceKey`
- raw `folderName`
- raw `downloadSessionId`
- raw `canonicalComicId`
- raw `upstreamComicRefId`
- raw `chapterRefId`
- raw local file path
- raw cache path
- raw archive path
- raw filename
- raw URL
- raw M12/M13/M14/M16/M17 artifacts

The approved executor owns:

- final navigation into ReaderNext presentation
- redacted navigation diagnostics
- rejecting malformed request payloads before navigation

The approved executor does not own:

- identity derivation
- SourceRef reconstruction
- readiness decisions
- fallback behavior
- feature flag interpretation

## Bridge/Controller Boundary

History, favorites, and downloads pages may only:

- pass row/page context into their approved bridge/controller path
- receive a controller decision
- dispatch the injected executor callback when decision is `readerNextEligible`
- dispatch explicit legacy callback when decision is `legacyExplicit`
- render/emit blocked state when decision is `blocked`

Pages must not:

- construct `ReaderNextOpenRequest`
- construct `SourceRef`
- import ReaderNext runtime
- import ReaderNext presentation screen/page
- import executor implementation directly
- parse canonical/upstream/chapter IDs
- inspect M12/M13/M14/M16/M17 raw artifacts

## Tasks

| Task ID | Deliverable                                                                     | Verification              |
| ------- | ------------------------------------------------------------------------------- | ------------------------- |
| M18-T1  | approved ReaderNext navigation executor interface/implementation                | unit test                 |
| M18-T2  | approved executor rejects malformed/unvalidated requests                        | unit test                 |
| M18-T3  | bridge factories return approved executor without page importing implementation | authority/widget test     |
| M18-T4  | history eligible path dispatches approved executor through injected seam        | smoke/widget test         |
| M18-T5  | favorites eligible path dispatches approved executor through injected seam      | smoke/widget test         |
| M18-T6  | downloads eligible path dispatches approved executor through injected seam      | smoke/widget test         |
| M18-T7  | blocked decisions across all entrypoints never call approved executor           | controller/widget test    |
| M18-T8  | flag-off decisions across all entrypoints use explicit legacy only              | controller/widget test    |
| M18-T9  | diagnostics are redacted for approved executor navigation                       | diagnostic test           |
| M18-T10 | authority guard: pages have no runtime/screen/request/sourceRef construction    | grep-backed test          |
| M18-T11 | regression guard: M14/M16/M17 semantics unchanged                               | authority/regression test |

## Acceptance Tests

```dart
test('approved executor accepts only ReaderNextOpenRequest', () {
  // expect raw row/source/path values are not accepted by API
});

test('approved executor rejects malformed request before navigation', () {
  // malformed SourceRef / missing canonical id / invalid upstream id
  // expect typed blocked/rejected result
  // expect no navigation
});

testWidgets('history eligible path uses approved executor through injected seam', (tester) async {
  // flag on + eligible history
  // expect approved executor call count == 1
  // expect page has no direct ReaderNext screen import
});

testWidgets('favorites eligible path uses approved executor through injected seam', (tester) async {
  // flag on + eligible favorite
  // expect approved executor call count == 1
  // expect folder-scoped identity remains controller-owned
});

testWidgets('downloads eligible path uses approved executor through injected seam', (tester) async {
  // flag on + eligible download
  // expect approved executor call count == 1
  // expect downloads page passes no raw local/cache/path identity
});

testWidgets('blocked decisions never call approved executor', (tester) async {
  // blocked history/favorites/downloads rows
  // expect executor count == 0 for all
  // expect no legacy fallback
});

testWidgets('flag off decisions call only explicit legacy route', (tester) async {
  // all three entrypoints flag off
  // expect legacy called once per attempt
  // expect approved executor count == 0
});

test('approved executor diagnostics are redacted', () {
  // navigation packet must not contain raw canonical/upstream/chapter/path/url/token/header values
});

test('production pages do not import ReaderNext navigation implementation', () async {
  // grep history/favorites/downloads pages
  // expect no ReaderNext presentation screen/page import
  // expect no executor implementation import
  // expect no ReaderNextOpenRequest construction
  // expect no SourceRef construction
});
```

## Authority Guards

Required guard coverage:

- `history_page.dart` does not import ReaderNext runtime or presentation screen/page classes.
- favorites pages do not import ReaderNext runtime or presentation screen/page classes.
- downloads pages do not import ReaderNext runtime or presentation screen/page classes.
- production pages do not import approved executor implementation directly.
- production pages do not construct `ReaderNextOpenRequest`.
- production pages do not construct `SourceRef`.
- production pages do not parse canonical/upstream/chapter IDs.
- blocked branches do not call approved executor or legacy fallback.
- raw M12/M13/M14/M16/M17 artifacts are not consumed by pages as route authority.

Suggested guard commands:

```bash
rg -n "features/reader_next/(runtime|presentation)|ReaderNext.*Page|ReaderNext.*Screen|ApprovedReaderNextNavigationExecutor|ReaderNextNavigationExecutor" \
  lib/pages/history_page.dart lib/pages/favorites lib/pages/downloading_page.dart lib/pages/local_comics_page.dart \
  -g '!*.g.dart'

rg -n "ReaderNextOpenRequest\\(|SourceRef\\.|upstreamComicRefId|chapterRefId|fromLegacyRemote|canonicalComicId" \
  lib/pages/history_page.dart lib/pages/favorites lib/pages/downloading_page.dart lib/pages/local_comics_page.dart \
  -g '!*.g.dart'

rg -n "IdentityCoverageReport|BackfillApplyPlan|history_favorites_identity_preflight|downloads_route_readiness_preflight|ReadinessArtifact" \
  lib/pages/history_page.dart lib/pages/favorites lib/pages/downloading_page.dart lib/pages/local_comics_page.dart \
  -g '!*.g.dart'

rg -n "blocked[\\s\\S]{0,240}(openLegacy|approvedExecutor|navigationExecutor)|(?:openLegacy|approvedExecutor|navigationExecutor)[\\s\\S]{0,240}blocked" \
  lib/features/reader_next/bridge lib/pages/history_page.dart lib/pages/favorites lib/pages/downloading_page.dart lib/pages/local_comics_page.dart test/features/reader_next test/pages \
  -g '!*.g.dart'
```

Expected:

- no page-level ReaderNext runtime/screen/executor implementation imports.
- no page-level request or SourceRef construction.
- no page-level raw artifact authority usage.
- no blocked-to-legacy or blocked-to-executor branch.

## Verification Commands

```bash
flutter test test/features/reader_next/presentation/*navigation_executor*
flutter test test/pages/history_page_m15_test.dart
flutter test test/pages/favorites_page_m16_2_test.dart
flutter test test/pages/downloads_page_m17_4_test.dart
flutter test test/pages/downloads_page_m17_3_test.dart
flutter test test/features/reader_next/bridge/*downloads*
flutter test test/features/reader_next/runtime/*authority*
dart analyze lib/features/reader_next/bridge lib/features/reader_next/presentation lib/pages/history_page.dart lib/pages/favorites lib/pages/downloading_page.dart lib/pages/local_comics_page.dart test/features/reader_next test/pages
git diff --check
```

## M18 Closeout Evidence

M18 completed as approved ReaderNext navigation executor consolidation.

Verified:

- a single approved navigation executor was added as the final ReaderNext open path
- bridge resolver/factory/dispatch code centralizes approved executor access
- history, favorites, and downloads executor seams dispatch through the approved executor contract
- downloads eligible output now carries a validated bridge request without page-level request construction
- blocked decisions remain terminal and do not call approved executor or legacy fallback
- flag-off decisions remain explicit legacy only
- production pages remain free of ReaderNext runtime/screen/executor implementation imports
- production pages do not construct `ReaderNextOpenRequest` or `SourceRef`
- diagnostics remain redacted by default
- M14/M16/M17 route authority semantics remain unchanged

Final verification:

1. `flutter test test/features/reader_next/presentation/*navigation_executor*`
   - Result: All tests passed (+2)
2. `flutter test test/pages/history_page_m15_test.dart`
   - Result: All tests passed (+2)
3. `flutter test test/pages/favorites_page_m16_2_test.dart`
   - Result: All tests passed (+6)
4. `flutter test test/pages/downloads_page_m17_4_test.dart`
   - Result: All tests passed (+6)
5. `flutter test test/pages/downloads_page_m17_3_test.dart`
   - Result: All tests passed (+5)
6. `flutter test test/features/reader_next/bridge/*downloads*`
   - Result: All tests passed (+5)
7. `flutter test test/features/reader_next/runtime/*authority*`
   - Result: All tests passed (+24)
8. `dart analyze lib/features/reader_next/bridge lib/features/reader_next/presentation lib/pages/history_page.dart lib/pages/favorites lib/pages/downloading_page.dart lib/pages/local_comics_page.dart test/features/reader_next test/pages`
   - Result: No issues found
9. `git diff --check`
   - Result: clean, no output

## Exit Criteria

- approved executor is the only code allowed to import ReaderNext presentation screen/page for final navigation.
- history eligible path dispatches approved executor through injected seam.
- favorites eligible path dispatches approved executor through injected seam.
- downloads eligible path dispatches approved executor through injected seam.
- blocked decisions never call approved executor or legacy fallback.
- flag-off decisions call explicit legacy only.
- pages remain free of ReaderNext runtime/screen/executor implementation imports.
- pages do not construct `ReaderNextOpenRequest` or `SourceRef`.
- diagnostics are redacted by default.
- M14/M16/M17 route authority semantics remain unchanged.
