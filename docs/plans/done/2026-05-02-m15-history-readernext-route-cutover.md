# M15 History ReaderNext Route Cutover

Goal:

- Enable exactly one non-detail ReaderNext entrypoint: history only.
- Consume M14 readiness artifact only.
- Keep favorites/downloads disabled.

Scope:

- history route wiring only
- no favorites route wiring
- no downloads route wiring
- no broad UI cutover
- no fallback after ReaderNext block
- no identity reconstruction
- no raw M12/M13 artifact route authority

## Hard Rules

1. History route may consume only M14 readiness artifact.
2. History route must validate current row before open.
3. History route must call bridge/controller only.
4. History route must not construct `ReaderNextOpenRequest` directly.
5. Feature flag controls route selection only.
6. If M14 says blocked, render blocked state and do not open legacy reader.
7. Favorites/downloads remain blocked even if their readiness is true.
8. No UI code may parse canonical IDs or derive upstream IDs.
9. History decision packet must include `readinessArtifactSchemaVersion` and `currentSourceRefValidationCode`.
10. No production page outside approved history cutover wiring may reference `ReaderNextOpenBridge` / `OpenReaderController`.
11. M15 must not read M12 report or M13 apply report as route authority.
12. M15 must not enable ReaderNext from favorites/downloads by shared helper side effect.

## Flag Contract

- New flag: `reader_next_history_enabled`
- Default: `false`
- Meaning:
  - `false`: history path must not attempt ReaderNext
  - `true`: history path may attempt ReaderNext only after M14 readiness + per-row validation pass
- Forbidden semantics:
  - bypassing M14 blocked decision
  - relaxing SourceRef validation
  - triggering legacy fallback on ReaderNext blocked result
  - enabling favorites/downloads ReaderNext paths

## Approved Production Wiring Exception

After M15, the only approved non-ReaderNext production history wiring may live in:

- `lib/pages/history_page.dart`

Approved file constraints:

- may call the approved history cutover controller / bridge-facing function
- must not construct `ReaderNextOpenRequest`
- must not import ReaderNext runtime files directly
- must not import ReaderNext presentation page/screen directly
- must not derive `upstreamComicRefId` from `History.id`
- must not read M12/M13 artifacts directly

If implementation needs helper/controller code, put it under:

- `lib/features/reader_next/bridge/`
- `lib/features/reader_next/presentation/`

## M14 Input Contract

M15 may consume only an M14 readiness artifact or an interface representing it.

Required fields for route decision:

- `readinessArtifactSchemaVersion`
- `historyReady`
- `favoritesReady`
- `downloadsReady`
- current-row validation result
- `recordKind=history`
- `recordId`
- `sourceKey`
- `candidateId` or `observedIdentityFingerprint`
- `currentSourceRefValidationCode`

Rules:

- stale/unknown readiness artifact schema blocks history route
- `historyReady=false` blocks history route even if row identity is valid
- current-row invalid state blocks history route even if `historyReady=true`
- `favoritesReady` and `downloadsReady` must be ignored by the history route controller
- M13 apply success must not be treated as route permission

## Tasks

| Task ID | Deliverable                                                        | Verification     |
| ------- | ------------------------------------------------------------------ | ---------------- |
| M15-T1  | history route controller consuming M14 readiness artifact only     | controller test  |
| M15-T2  | history open path calls bridge-only route preparation              | widget/page test |
| M15-T3  | blocked state for stale/missing/malformed history rows             | widget test      |
| M15-T4  | feature flag test: flag cannot bypass M14 blocked decision         | controller test  |
| M15-T5  | authority guard: favorites/downloads still cannot route ReaderNext | grep-backed test |
| M15-T6  | diagnostic packet for history open attempt                         | diagnostic test  |
| M15-T7  | guard that route code does not consume raw M12/M13 artifacts       | grep-backed test |

## Suggested Write Scope

Allowed:

- `lib/pages/history_page.dart`
- `lib/features/reader_next/bridge/*`
- `lib/features/reader_next/presentation/*`
- `test/pages/history_page_m15_test.dart`
- `test/features/reader_next/presentation/*`
- `test/features/reader_next/runtime/*authority*`

Forbidden:

- old reader runtime files
- favorites route/page files, except authority tests reading them
- downloads route/page files, except authority tests reading them
- M12/M13 preflight/backfill implementation changes unless only adding test fixtures
- any code path that imports `reader_next/runtime` from `lib/pages`, `lib/foundation`, or `lib/components`

## Route Decision Model

M15 history open attempt must produce one of:

- `legacyExplicit`
  - feature flag off
  - only explicit legacy history route is used
- `readerNextEligible`
  - feature flag on
  - M14 artifact schema valid
  - `historyReady=true`
  - current history row has valid SourceRef
  - bridge returns valid open request
- `blocked`
  - feature flag on
  - M14 blocks the entrypoint or row
  - bridge blocks the request
  - no legacy fallback

Blocked reasons must be typed, not string-parsed UI guesses.

## Diagnostic Packet Contract

Each history open attempt must emit a dry-run style decision packet containing:

- `entrypoint`: `history`
- `routeDecision`: `legacyExplicit | readerNextEligible | blocked`
- `featureFlagEnabled`
- `readinessArtifactSchemaVersion`
- `sourceKey`
- `recordIdHash` or redacted record id
- `candidateId` or `observedIdentityFingerprint`
- `currentSourceRefValidationCode`
- `bridgeResultCode`
- `blockedReason`

Diagnostics must not include raw cookies, headers, tokens, or full upstream IDs by default.

## Acceptance Tests

```dart
test('history flag off uses explicit legacy route and does not call ReaderNext bridge', () {
  // reader_next_history_enabled=false
  // expect legacy callback called once
  // expect ReaderNext bridge/controller not called
});

test('history flag on but M14 blocks row does not fall back to legacy', () {
  // reader_next_history_enabled=true
  // M14 route decision = blocked
  // expect blocked state rendered
  // expect legacy callback not called
  // expect ReaderNext route callback not called
});

test('history flag cannot bypass stale current row validation', () {
  // reader_next_history_enabled=true
  // historyReady=true
  // currentSourceRefValidationCode=stale or malformed
  // expect blocked
});

test('history cutover ignores favorites and downloads readiness', () {
  // historyReady=false, favoritesReady=true, downloadsReady=true
  // expect history route blocked
});

test('history decision packet includes schema version and current validation code', () {
  // assert readinessArtifactSchemaVersion is present
  // assert currentSourceRefValidationCode is present
});
```

## Authority Guards

Required guard coverage:

- no direct `ReaderNextOpenRequest(` outside `lib/features/reader_next/**`
- history path uses bridge/controller only
- favorites/downloads paths do not reference:
  - `ReaderNextOpenBridge`
  - `OpenReaderController`
  - `ReaderNextOpenRequest(`
- no `SourceRef.remote(... upstreamComicRefId: <row>.id)` reconstruction pattern
- no legacy reader/runtime/component directory imports:
  - `reader_next/runtime`
  - `reader_next/presentation`
- no route code consumes raw M12/M13 apply output as route authority

Suggested guard commands:

```bash
rg -n "ReaderNextOpenRequest\\(" lib \
  -g '!lib/features/reader_next/**' \
  -g '!*.g.dart'

rg -n "ReaderNextOpenBridge|OpenReaderController" \
  lib/pages/history_page.dart \
  lib/pages/favorites \
  lib/pages/local_comics_page.dart \
  -g '!*.g.dart'

rg -n "SourceRef\\.remote\\([\\s\\S]{0,240}upstreamComicRefId:\\s*(history|favorite|item|comic)\\.id" lib test

rg -n "features/reader_next/(runtime|presentation)" lib/pages lib/foundation lib/components -g '!*.g.dart'

rg -n "M12|M13|BackfillApplyPlan|IdentityCoverageReport|explicit_identity_backfill" \
  lib/pages lib/features/reader_next/presentation lib/features/reader_next/bridge \
  -g '!*.g.dart'
```

Expected:

- history approved wiring file(s) only for bridge/controller references
- no favorites/downloads ReaderNext route references
- no direct request construction outside reader_next
- no upstream ID reconstruction from row IDs
- no M12/M13 artifact route authority usage

## Verification Commands

```bash
flutter test test/pages/history_page_m15_test.dart
flutter test test/features/reader_next/presentation
flutter test test/features/reader_next/runtime/*authority*
dart analyze lib/pages/history_page.dart lib/features/reader_next/bridge lib/features/reader_next/presentation test/pages/history_page_m15_test.dart test/features/reader_next
git diff --check
```

## M15.1 Approved ReaderNext Navigation Executor

Goal:

- Convert an approved `ReaderNextOpenRequest` into actual ReaderNext presentation navigation.
- Keep production pages unaware of ReaderNext screen/runtime classes.
- Preserve M15 history-only cutover boundary.

Scope:

- approved navigation executor wiring only
- history eligible path only
- no favorites route wiring
- no downloads route wiring
- no fallback after blocked result
- no identity reconstruction

### Hard Rules

1. `lib/pages/history_page.dart` must not import ReaderNext runtime files.
2. `lib/pages/history_page.dart` must not import ReaderNext presentation page/screen classes.
3. `lib/pages/history_page.dart` must not construct `ReaderNextOpenRequest` directly.
4. The navigation executor must live under `lib/features/reader_next/presentation/` or an approved bridge-facing adapter.
5. The executor may accept only `ReaderNextOpenRequest` as its navigation input.
6. The executor must not rebuild identity, parse canonical IDs, or derive upstream IDs.
7. Blocked results must never reach the executor.
8. Blocked results must not trigger legacy fallback.
9. Favorites/downloads remain disabled and must not reference ReaderNext bridge, controller, executor, or presentation route classes.
10. Only the approved executor may import the ReaderNext presentation screen/page.

### Tasks

| Task ID  | Deliverable                                                                                | Verification                 |
| -------- | ------------------------------------------------------------------------------------------ | ---------------------------- |
| M15.1-T1 | approved ReaderNext navigation executor                                                    | executor unit/widget test    |
| M15.1-T2 | history eligible path dispatches to executor through injected callback/adapter             | history page/controller test |
| M15.1-T3 | blocked path never calls executor                                                          | controller test              |
| M15.1-T4 | authority guard: history page has no ReaderNext runtime/screen imports                     | grep-backed test             |
| M15.1-T5 | authority guard: favorites/downloads still cannot reference ReaderNext route/executor path | grep-backed test             |

### Executor Contract

The executor input must be:

- `ReaderNextOpenRequest request`

The executor must not accept:

- raw `recordId`
- raw `History.id`
- raw `canonicalComicId` string requiring parsing
- raw `upstreamComicRefId`
- M12 report data
- M13 apply report data

The executor may perform presentation navigation only after receiving a fully validated request.

### Required Tests

```dart
test('eligible history path calls ReaderNext executor once', () {
  // M14 historyReady=true
  // current row valid
  // bridge returns ReaderNextOpenRequest
  // expect executor call count == 1
  // expect legacy callback call count == 0
});

test('blocked history path never calls ReaderNext executor', () {
  // M14 blocked or bridge blocked
  // expect executor call count == 0
  // expect legacy callback call count == 0
});

test('history page remains unaware of ReaderNext presentation screen', () async {
  // read lib/pages/history_page.dart
  // expect no ReaderNextShellPage / ReaderNextPage / reader_next/runtime import
});
```

### Additional Guard Commands

```bash
rg -n "ReaderNextShellPage|ReaderNext.*Page|ReaderNext.*Screen" lib/pages lib/foundation lib/components -g '!*.g.dart'

rg -n "ReaderNextOpenRequest\\(" lib/pages lib/foundation lib/components -g '!*.g.dart'

rg -n "ReaderNextOpenBridge|OpenReaderController|ReaderNextNavigationExecutor" \
  lib/pages/favorites lib/pages/local_comics_page.dart lib/pages/downloads \
  -g '!*.g.dart'

rg -n "features/reader_next/(runtime|presentation)" lib/pages/history_page.dart -g '!*.g.dart'
```

Expected:

- `history_page.dart` has no ReaderNext runtime import.
- `history_page.dart` has no ReaderNext screen/page import.
- only the approved executor imports the ReaderNext screen/page.
- blocked route decisions do not reach executor.
- favorites/downloads remain free of ReaderNext route/executor references.

### M15.1 Exit Criteria

- eligible history route dispatches exactly once to approved executor.
- blocked history route dispatches zero times to approved executor.
- legacy fallback is not called after ReaderNext blocked result.
- production pages remain unaware of ReaderNext presentation screen classes.
- favorites/downloads remain disabled.

## M15.2 History ReaderNext Cutover Observability + Rollback Guard

Goal:

- Make the history ReaderNext cutover observable and safely reversible.
- Keep the cutover limited to the approved history entrypoint.
- Do not add any new ReaderNext entrypoints.

Scope:

- history observability only
- rollback guard only
- no favorites route wiring
- no downloads route wiring
- no new runtime identity behavior
- no fallback after ReaderNext block
- no identity reconstruction

### Hard Rules

1. Every history open attempt must emit a route decision diagnostic packet.
2. Diagnostic packets must include route decision, feature flag state, readiness artifact schema version, and current validation code.
3. Diagnostic packets must not include raw canonical IDs, raw upstream IDs, cookies, headers, tokens, or full URLs by default.
4. Turning `reader_next_history_enabled=false` must return history opens to the explicit legacy route.
5. Turning `reader_next_history_enabled=false` must not mutate readiness artifacts, SourceRef snapshots, or history rows.
6. Blocked ReaderNext decisions remain terminal and must not fall back to legacy.
7. Favorites/downloads remain disabled and must not gain ReaderNext route references.
8. UI route switching may consume only M14 readiness artifacts, never raw M12/M13 artifacts.
9. Rollback behavior must be controlled only by route-selection flags, not by weakening SourceRef validation.
10. Observability code must not parse canonical IDs or derive upstream IDs.

### Tasks

| Task ID  | Deliverable                                                                                      | Verification           |
| -------- | ------------------------------------------------------------------------------------------------ | ---------------------- |
| M15.2-T1 | history route decision diagnostic emitted for every open attempt                                 | diagnostic test        |
| M15.2-T2 | rollback flag behavior: disabling `reader_next_history_enabled` returns to explicit legacy route | controller/widget test |
| M15.2-T3 | blocked route diagnostic includes typed blocked reason and current validation code               | diagnostic test        |
| M15.2-T4 | redaction guard: no raw canonical/upstream IDs in diagnostic packet                              | unit test              |
| M15.2-T5 | authority guard: observability code does not read M12/M13 raw artifacts as route authority       | grep-backed test       |
| M15.2-T6 | authority guard: favorites/downloads remain ReaderNext-disabled                                  | grep-backed test       |

### Diagnostic Packet Contract

Each history open attempt must emit:

- `entrypoint`: `history`
- `routeDecision`: `legacyExplicit | readerNextEligible | blocked`
- `featureFlagEnabled`
- `historyFeatureFlagEnabled`
- `readinessArtifactSchemaVersion`
- `currentSourceRefValidationCode`
- `bridgeResultCode`
- `blockedReason`
- `sourceKey`
- `recordIdHash` or redacted record id
- `candidateId` or `observedIdentityFingerprint`

The packet must not emit:

- raw `canonicalComicId`
- raw `upstreamComicRefId`
- raw `chapterRefId`
- raw cookies
- raw request headers
- bearer tokens
- full source URLs
- M12 report payloads
- M13 apply report payloads

### Rollback Contract

Rollback means:

- `reader_next_history_enabled=false`
- history open uses the explicit legacy route
- ReaderNext bridge/controller/executor is not called
- M14 readiness artifact remains unchanged
- no SourceRef snapshot is changed
- no history/favorites/download route enablement changes

Rollback does not mean:

- accepting malformed SourceRef
- falling back after a blocked ReaderNext attempt
- changing M14 readiness decisions
- reading M13 apply report as route authority

### Required Tests

```dart
test('history open emits diagnostic packet for legacy explicit decision', () {
  // reader_next_history_enabled=false
  // expect routeDecision=legacyExplicit
  // expect historyFeatureFlagEnabled=false
  // expect ReaderNext bridge/executor not called
});

test('history rollback flag returns to explicit legacy route', () {
  // first: flag on + eligible => ReaderNext executor called
  // then: flag off => legacy callback called
  // expect no readiness/sourceRef mutation
});

test('blocked history diagnostic is redacted and does not fallback', () {
  // flag on + malformed/stale row
  // expect routeDecision=blocked
  // expect currentSourceRefValidationCode present
  // expect raw canonical/upstream ids absent
  // expect legacy callback not called
});
```

### Authority Guards

Required guard coverage:

- observability code must not import M12/M13 preflight/backfill as route authority.
- history page must not import ReaderNext runtime or presentation screen classes.
- favorites/downloads must not reference ReaderNext bridge/controller/executor classes.
- diagnostic payload builders must not expose raw canonical or upstream ID fields.
- no code may use rollback flags to bypass M14 current-row validation.

Suggested guard commands:

```bash
rg -n "IdentityCoverageReport|BackfillApplyPlan|explicit_identity_backfill|history_favorites_identity_preflight" \
  lib/pages lib/features/reader_next/bridge lib/features/reader_next/presentation \
  -g '!*.g.dart'

rg -n "canonicalComicId|upstreamComicRefId|chapterRefId" \
  lib/features/reader_next/bridge lib/features/reader_next/presentation \
  -g '!*.g.dart'

rg -n "ReaderNextOpenBridge|OpenReaderController|ReaderNextHistoryOpenExecutor|ReaderNextNavigationExecutor" \
  lib/pages/favorites lib/pages/local_comics_page.dart lib/pages/downloads \
  -g '!*.g.dart'

rg -n "features/reader_next/(runtime|presentation)" lib/pages/history_page.dart -g '!*.g.dart'
```

Expected:

- no raw M12/M13 artifact route authority usage.
- no raw canonical/upstream ID fields are emitted in diagnostics.
- no favorites/downloads ReaderNext route references.
- `history_page.dart` remains unaware of ReaderNext runtime/screen classes.

## M15.2 Closeout Evidence

M15.2 completed as observability + rollback guard only.

Verified:

- every history open attempt emits a `HistoryRouteDecisionDiagnosticPacket`
- diagnostics are emitted from the bridge/controller layer, not assembled in `history_page.dart`
- `legacyExplicit`, `readerNextEligible`, and `blocked` decisions are all covered
- blocked decisions are terminal: no legacy fallback and no ReaderNext executor call
- disabling `reader_next_history_enabled` returns history opens to explicit legacy route
- diagnostic packets are redacted by default
- route authority does not consume raw M12/M13 artifacts
- favorites/downloads remain ReaderNext-disabled

Final verification:

1. `flutter test test/features/reader_next/bridge/history_route_cutover_controller_test.dart`
   - Result: All tests passed (+9)
2. `flutter test test/features/reader_next/runtime/*authority*`
   - Result: All tests passed (+16)
3. `dart analyze lib/pages/history_page.dart lib/features/reader_next/bridge lib/features/reader_next/presentation test/features/reader_next`
   - Result: No issues found
4. `git diff --check`
   - Result: clean, no output

### M15.2 Exit Criteria

- every history open attempt has a diagnostic decision packet.
- disabling `reader_next_history_enabled` returns history opens to explicit legacy route.
- blocked ReaderNext decisions remain terminal and do not fallback.
- diagnostic packets are redacted by default.
- favorites/downloads remain disabled.
- no M12/M13 raw artifact is consumed as route authority.

## M15.3 History ReaderNext Runtime Smoke + Kill-Switch Verification

Goal:

- Verify the actual history ReaderNext cutover path behaves safely in app-level smoke tests.
- Prove kill-switch rollback works without touching identity/readiness state.
- Keep favorites/downloads disabled.

Scope:

- smoke/integration tests only
- history entrypoint only
- no new ReaderNext entrypoints
- no favorites route wiring
- no downloads route wiring
- no identity reconstruction
- no fallback after blocked ReaderNext decision

### Hard Rules

1. M15.3 must not add new production entrypoints.
2. M15.3 must not enable favorites or downloads ReaderNext routes.
3. Kill-switch `reader_next_history_enabled=false` affects route selection only.
4. Kill-switch must not mutate M14 readiness artifact, identity snapshots, SourceRef snapshots, history rows, favorites rows, or downloads rows.
5. Smoke tests must prove `reader_next_history_enabled=false` returns history opens to explicit legacy route.
6. Smoke tests must prove `reader_next_history_enabled=true` still cannot bypass M14 current-row validation.
7. Smoke tests must prove blocked history rows do not call legacy fallback or ReaderNext executor.
8. Smoke tests must prove favorites/downloads do not get executor wiring even if their readiness values are true.
9. Diagnostic smoke must verify redacted packets for `legacyExplicit`, `readerNextEligible`, and `blocked` decisions.
10. No UI code may parse canonical IDs, derive upstream IDs, or read raw M12/M13 artifacts.

### Tasks

| Task ID  | Deliverable                                                                                                                        | Verification            |
| -------- | ---------------------------------------------------------------------------------------------------------------------------------- | ----------------------- |
| M15.3-T1 | app-level smoke: flag off history uses explicit legacy route                                                                       | widget/integration test |
| M15.3-T2 | app-level smoke: flag on + eligible history calls approved executor                                                                | widget/integration test |
| M15.3-T3 | app-level smoke: flag on + blocked history renders blocked state and does not fallback                                             | widget/integration test |
| M15.3-T4 | kill-switch test: toggling `reader_next_history_enabled=false` stops ReaderNext attempts without mutating readiness/identity state | controller/widget test  |
| M15.3-T5 | diagnostic smoke: all three decisions emit redacted packets                                                                        | diagnostic test         |
| M15.3-T6 | authority guard: favorites/downloads still have no ReaderNext executor wiring                                                      | grep-backed test        |

### Smoke Decision Matrix

| State                                                 | Expected Decision          | Legacy Callback | ReaderNext Executor | Blocked Callback |
| ----------------------------------------------------- | -------------------------- | --------------- | ------------------- | ---------------- |
| `reader_next_history_enabled=false`                   | `legacyExplicit`           | called once     | not called          | not called       |
| `reader_next_history_enabled=true` + history eligible | `readerNextEligible`       | not called      | called once         | not called       |
| `reader_next_history_enabled=true` + history blocked  | `blocked`                  | not called      | not called          | called once      |
| favorites/downloads readiness true                    | ignored by history cutover | unchanged       | not wired           | unchanged        |

### Kill-Switch Contract

Kill-switch means:

- set `reader_next_history_enabled=false`
- history open returns to explicit legacy route
- ReaderNext bridge/executor is not called for history
- M14 readiness artifact is not changed
- SourceRef snapshots are not changed
- history/favorites/download records are not changed
- favorites/downloads remain disabled

Kill-switch does not mean:

- fallback after a blocked ReaderNext decision
- accepting malformed SourceRef
- bypassing current-row validation
- changing M14 readiness decisions
- enabling or disabling other entrypoints

### Required Tests

```dart
testWidgets('runtime smoke: flag off history uses explicit legacy route', (tester) async {
  // reader_next_history_enabled=false
  // expect routeDecision=legacyExplicit
  // expect legacy callback count == 1
  // expect ReaderNext executor count == 0
});

testWidgets('runtime smoke: flag on eligible history opens ReaderNext executor once', (tester) async {
  // reader_next_history_enabled=true
  // M14 historyReady=true
  // current row valid
  // expect routeDecision=readerNextEligible
  // expect executor count == 1
  // expect legacy callback count == 0
});

testWidgets('runtime smoke: blocked history does not fallback', (tester) async {
  // reader_next_history_enabled=true
  // M14 blocks row or current row invalid
  // expect routeDecision=blocked
  // expect blocked callback/rendered state
  // expect legacy callback count == 0
  // expect executor count == 0
});

test('kill-switch does not mutate readiness or identity state', () {
  // capture readiness artifact + SourceRef snapshot before toggle
  // toggle reader_next_history_enabled=false
  // assert captured state unchanged
});

test('favorites downloads readiness true does not create executor wiring', () {
  // readiness artifact may say favorites/downloads ready
  // history cutover must ignore them
  // authority guard verifies no favorites/downloads executor references
});
```

### Authority Guards

Required guard coverage:

- favorites/downloads must not reference ReaderNext bridge/controller/executor classes.
- history page must not import ReaderNext runtime or presentation screen classes.
- no direct `ReaderNextOpenRequest(` outside `lib/features/reader_next/**`.
- no route code reads M12/M13 raw artifacts as authority.
- no blocked branch calls legacy route.
- no diagnostic packet exposes raw canonical/upstream/chapter IDs.

Suggested guard commands:

```bash
rg -n "ReaderNextOpenRequest\\(" lib -g '!lib/features/reader_next/**' -g '!*.g.dart'

rg -n "ReaderNextOpenBridge|OpenReaderController|ReaderNextHistoryOpenExecutor|ReaderNextNavigationExecutor" \
  lib/pages/favorites lib/pages/local_comics_page.dart lib/pages/downloads \
  -g '!*.g.dart'

rg -n "features/reader_next/(runtime|presentation)" lib/pages/history_page.dart -g '!*.g.dart'

rg -n "IdentityCoverageReport|BackfillApplyPlan|explicit_identity_backfill|history_favorites_identity_preflight" \
  lib/pages lib/features/reader_next/bridge lib/features/reader_next/presentation \
  -g '!*.g.dart'

rg -n "blocked[\\s\\S]{0,240}openLegacy|openLegacy[\\s\\S]{0,240}blocked" \
  lib/features/reader_next/bridge lib/pages/history_page.dart test/features/reader_next test/pages \
  -g '!*.g.dart'
```

Expected:

- no favorites/downloads ReaderNext executor wiring.
- no history page ReaderNext runtime/screen import.
- no direct request construction outside ReaderNext internals.
- no M12/M13 route authority usage.
- no blocked-to-legacy branch.

### M15.3 Closeout Evidence

M15.3 completed as runtime smoke + kill-switch verification only.

Verified:

- flag off history open uses explicit legacy route
- flag on + eligible history open calls approved ReaderNext executor exactly once
- flag on + blocked history open is terminal: no legacy fallback and no executor call
- kill-switch does not mutate readiness or identity state
- diagnostics cover `legacyExplicit`, `readerNextEligible`, and `blocked`
- diagnostics are redacted by default
- favorites/downloads remain without ReaderNext executor wiring
- `history_page.dart` remains bridge/controller-only and does not assemble internal diagnostic fields

Final verification:

1. `flutter test test/features/reader_next/bridge/history_route_cutover_m15_3_smoke_test.dart test/features/reader_next/bridge/history_route_cutover_controller_test.dart`
   - Result: All tests passed (+14)
2. `flutter test test/features/reader_next/runtime/*authority*`
   - Result: All tests passed (+16)
3. `dart analyze lib/pages/history_page.dart lib/features/reader_next/bridge lib/features/reader_next/presentation test/features/reader_next`
   - Result: No issues found
4. `git diff --check`
   - Result: clean, no output

### M15.3 Exit Criteria

- app-level history smoke proves flag-off explicit legacy route.
- app-level history smoke proves flag-on eligible route calls approved executor once.
- app-level history smoke proves blocked rows are terminal and do not fallback.
- kill-switch does not mutate readiness or identity state.
- diagnostics are emitted and redacted for all three decision classes.
- favorites/downloads remain disabled even if readiness values are true.

## Exit Criteria

- only history can attempt ReaderNext
- favorites/downloads remain disabled
- invalid history rows are blocked
- no fallback after ReaderNext block
- no direct `ReaderNextOpenRequest` construction outside reader_next
- feature flag does not bypass M14 readiness/current-row validation
- history decision packet includes `readinessArtifactSchemaVersion` and `currentSourceRefValidationCode`
- no M12/M13 raw artifact is consumed as route authority

## Out of Scope

- favorites route cutover (defer to M16)
- downloads route cutover (defer to M17)
- broad multi-entrypoint enablement
- importer/backfill mutation
- legacy runtime cleanup
