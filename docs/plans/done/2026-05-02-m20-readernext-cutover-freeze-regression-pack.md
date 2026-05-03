# M20 ReaderNext Cutover Freeze / Regression Pack

Goal:

- Freeze the ReaderNext production cutover lane after M19 final smoke.
- Consolidate the mandatory regression pack for future changes.
- Document rollback procedures for history, favorites, and downloads.
- Mark future cutover changes as bugfix-only unless a new ADR opens a new lane.

Scope:

- freeze and regression contract only
- no new ReaderNext entrypoints
- no new identity model
- no new feature flag semantics
- no new fallback behavior
- no SourceRef reconstruction
- no ReaderNext request construction in production pages
- no importer/backfill changes
- no UI redesign

## Freeze Statement

M20 freezes the current ReaderNext cutover lane.

The supported production entrypoints are:

- history
- favorites
- downloads

The approved route model is:

- page sends row/page context to bridge/controller
- bridge/controller owns route authority and validation
- eligible decision dispatches approved ReaderNext executor
- blocked decision is terminal
- flag-off decision uses explicit legacy route

No additional production entrypoint may join ReaderNext without a new ADR and a new staged cutover lane.

## Hard Rules

1. No new ReaderNext entrypoints after M20 without a new ADR.
2. No page-level `ReaderNextOpenRequest` construction.
3. No page-level `SourceRef` construction.
4. No page-level ReaderNext runtime import.
5. No page-level ReaderNext presentation screen/page import.
6. No page-level approved executor implementation import.
7. No blocked-to-legacy fallback.
8. No blocked-to-approved-executor dispatch.
9. No identity derivation from local path, cache path, archive path, filename, title, URL, or canonical ID string split.
10. No raw M14/M16/M17 artifact route authority in pages.
11. No feature flag may relax validation.
12. Feature flags control route selection only.
13. Kill-switches must not mutate readiness, identity, SourceRef snapshots, importer state, backfill state, or persisted rows.
14. Diagnostics must remain redacted by default.
15. Diagnostics must not expose raw canonical IDs, upstream IDs, chapter IDs, local paths, cache paths, archive paths, filenames, URLs, cookies, headers, or tokens.
16. Future changes must pass the M19 final smoke matrix and the M20 regression pack.
17. Any intentional change to M14/M16/M17 route authority semantics requires a new ADR.
18. Any intentional fallback behavior change requires a new ADR.

## Frozen Route Authority Matrix

| Entrypoint | Feature Flag                    | Route Authority                         | Identity Constraint                                        | Eligible Behavior      | Blocked Behavior | Flag-Off Behavior |
| ---------- | ------------------------------- | --------------------------------------- | ---------------------------------------------------------- | ---------------------- | ---------------- | ----------------- |
| history    | `reader_next_history_enabled`   | M14 readiness + current-row validation  | valid `SourceRef` only                                     | approved executor once | blocked terminal | explicit legacy   |
| favorites  | `reader_next_favorites_enabled` | M14 readiness + M16 favorites preflight | `folderName + recordId + sourceKey` plus valid `SourceRef` | approved executor once | blocked terminal | explicit legacy   |
| downloads  | `reader_next_downloads_enabled` | M14 readiness + M17 downloads preflight | explicit identity only; no storage-path inference          | approved executor once | blocked terminal | explicit legacy   |

## Rollback Procedures

### History rollback

Set:

```text
reader_next_history_enabled=false
```

Expected behavior:

- history open uses explicit legacy route
- approved executor is not called
- M14 readiness artifact is unchanged
- SourceRef snapshots are unchanged
- history rows are unchanged
- favorites/downloads flags and behavior are unchanged

### Favorites rollback

Set:

```text
reader_next_favorites_enabled=false
```

Expected behavior:

- favorites open uses explicit legacy route
- approved executor is not called
- M14 readiness artifact is unchanged
- M16 favorites preflight state is unchanged
- SourceRef snapshots are unchanged
- favorites rows are unchanged
- history/downloads flags and behavior are unchanged

### Downloads rollback

Set:

```text
reader_next_downloads_enabled=false
```

Expected behavior:

- downloads open uses explicit legacy route
- approved executor is not called
- M14 readiness artifact is unchanged
- M17 downloads preflight state is unchanged
- SourceRef snapshots are unchanged
- downloads rows are unchanged
- history/favorites flags and behavior are unchanged

## Regression Pack

Any future change touching ReaderNext route cutover must run this pack.

### Required test commands

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

### Required authority guards

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

- no page-level request construction
- no page-level SourceRef construction
- no page-level ReaderNext runtime/screen/executor implementation imports
- no page-level raw artifact authority usage
- no blocked-to-legacy branch
- no blocked-to-approved-executor branch

## Bugfix-Only Policy

After M20, allowed changes are limited to:

- fixing incorrect blocked decisions
- fixing incorrect flag-off route selection
- fixing redaction bugs
- fixing authority guard false positives without weakening the guarded invariant
- fixing tests or fixtures that no longer match the frozen contract
- improving diagnostics without adding raw sensitive fields
- improving internal code clarity without moving authority into pages

Not allowed without new ADR:

- new ReaderNext entrypoint
- new route fallback path
- page-level request construction
- page-level SourceRef construction
- page-level runtime/presentation import
- identity derivation from storage paths or canonical ID string split
- changing M14/M16/M17 authority semantics
- changing feature flag semantics from route selection into validation override
- accepting malformed or missing SourceRef as valid
- using raw M12/M13/M14/M16/M17 artifacts as page-level route authority

## Release Notes Requirements

Any release note for this lane must state:

- ReaderNext cutover is guarded by per-entrypoint feature flags.
- Rollback is done by disabling the relevant flag.
- Rollback does not mutate identity/readiness data.
- Blocked ReaderNext decisions do not fallback to legacy.
- Legacy is used only when the entrypoint flag is off.
- Diagnostics are redacted by default.

## M20 Verification Commands

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

- M20 regression pack is documented.
- rollback procedures are documented for history, favorites, and downloads.
- future changes are marked bugfix-only unless a new ADR opens a new lane.
- frozen route authority matrix is documented.
- authority guard expectations are documented.
- release note requirements are documented.
- no new route semantics are introduced.

## M20 Closeout Evidence

M20 completed as freeze/regression-contract lane only.  
No new route semantics, no new entrypoints, and no page-level authority expansion were introduced.

### Final Verification

1. `flutter test test/features/reader_next/presentation/*navigation_executor*`  
   Result: All tests passed (`+2`)
2. `flutter test test/pages/history_page_m15_test.dart`  
   Result: All tests passed (`+2`)
3. `flutter test test/pages/favorites_page_m16_2_test.dart`  
   Result: All tests passed (`+6`)
4. `flutter test test/pages/downloads_page_m17_4_test.dart`  
   Result: All tests passed (`+6`)
5. `flutter test test/pages/m19_production_cutover_final_smoke_test.dart`  
   Result: All tests passed (`+7`)
6. `flutter test test/features/reader_next/runtime/*authority*`  
   Result: All tests passed (`+24`)
7. `dart analyze lib/features/reader_next/bridge lib/features/reader_next/presentation lib/pages/history_page.dart lib/pages/favorites lib/pages/downloading_page.dart lib/pages/local_comics_page.dart test/features/reader_next test/pages`  
   Result: No issues found
8. `git diff --check`  
   Result: clean, no output

### Freeze Authority Confirmation

- history/favorites/downloads remain the only supported production ReaderNext entrypoints
- route authority remains controller-owned (page -> bridge/controller -> approved executor)
- blocked decisions remain terminal and do not fallback to legacy
- feature flags remain route-selection only and do not relax validation
- rollback remains flag-based and non-mutating for readiness/identity state
- diagnostics remain redacted-by-default with no raw sensitive identity/path/network data
