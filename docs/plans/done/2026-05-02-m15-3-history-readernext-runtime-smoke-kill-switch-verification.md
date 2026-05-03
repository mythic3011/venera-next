# M15.3 History ReaderNext Runtime Smoke + Kill-Switch Verification

Goal:
- verify the actual history ReaderNext cutover path behaves safely in app-level smoke tests
- prove kill-switch rollback works without touching identity/readiness state
- keep favorites/downloads disabled

Scope:
- smoke/integration tests only
- no new entrypoints
- no identity reconstruction
- no fallback after blocked
- no production semantics change

## Hard Rules

1. Kill-switch (`reader_next_history_enabled=false`) controls route selection only.
2. Kill-switch must not mutate M14 readiness artifact state or history row identity state.
3. `flag off` must use explicit legacy route and must not call bridge/executor.
4. `flag on + blocked` remains terminal: blocked only, no legacy fallback, no executor call.
5. `flag on + eligible` may call approved executor exactly once.
6. Diagnostics for all route decisions must be emitted from bridge/controller path, not assembled in `history_page.dart`.
7. Diagnostic packets must be redacted and must not contain raw canonical/upstream/chapter IDs.
8. Favorites/downloads remain disabled even if readiness says true.

## Tasks

| Task ID | Deliverable | Verification |
| --- | --- | --- |
| M15.3-T1 | app-level smoke: flag off history uses explicit legacy route | widget/integration test |
| M15.3-T2 | app-level smoke: flag on + eligible history calls approved executor | widget/integration test |
| M15.3-T3 | app-level smoke: flag on + blocked history renders blocked state, no legacy fallback | widget/integration test |
| M15.3-T4 | kill-switch test: toggling `reader_next_history_enabled=false` stops ReaderNext attempts | controller/widget test |
| M15.3-T5 | diagnostic smoke: all three decisions emit redacted packets | diagnostic test |
| M15.3-T6 | authority guard: favorites/downloads still disabled | grep-backed test |

## Required Tests

```dart
test('flag off uses explicit legacy route', () {
  // expect routeDecision=legacyExplicit
  // expect legacy callback called once
  // expect executor callback called zero
});

test('flag on + eligible calls approved executor once', () {
  // expect routeDecision=readerNextEligible
  // expect executor callback called once
  // expect legacy callback called zero
});

test('flag on + blocked stays blocked without fallback', () {
  // expect routeDecision=blocked
  // expect blocked callback called once
  // expect legacy/executor callbacks both zero
});

test('kill-switch does not mutate readiness/identity state', () {
  // evaluate with flag on then off
  // readiness artifact object remains unchanged
  // row identity fields remain unchanged
});

test('diagnostics for three decisions are redacted', () {
  // legacyExplicit / readerNextEligible / blocked
  // ensure recordIdRedacted does not expose raw id
  // ensure no raw canonical/upstream/chapter ids appear
});
```

## Authority Guard Commands

```bash
rg -n "ReaderNextOpenBridge|OpenReaderController|ReaderNextHistoryOpenExecutor|ReaderNextNavigationExecutor" \
  lib/pages/favorites lib/pages/local_comics_page.dart lib/pages/downloads \
  -g '!*.g.dart'

rg -n "case HistoryRouteDecision\\.blocked:[\\s\\S]{0,220}openLegacy\\(" \
  lib/features/reader_next/bridge/history_route_cutover_controller.dart

rg -n "canonicalComicId|upstreamComicRefId|chapterRefId" \
  lib/features/reader_next/bridge lib/features/reader_next/presentation \
  -g '!*.g.dart'
```

Expected:
- no favorites/downloads ReaderNext route references
- blocked branch does not call legacy callback
- diagnostic outputs stay redacted by contract

## Exit Criteria

- flag off path is explicit legacy and no ReaderNext attempt
- flag on + eligible calls executor exactly once
- flag on + blocked calls neither executor nor legacy fallback
- kill-switch does not mutate readiness/identity state
- three route decisions emit redacted diagnostics
- favorites/downloads remain disabled
