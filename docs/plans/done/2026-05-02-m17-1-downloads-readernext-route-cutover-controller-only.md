# M17.1 Downloads ReaderNext Route Cutover (Controller-Only)

Goal:

- define downloads cutover controller contract using M14 readiness + M17 downloads preflight only
- keep downloads page in row-context lane only
- do not wire downloads ReaderNext route or executor in this milestone

Scope:

- controller-only cutover contract
- route decision and diagnostic packet contract
- authority guards
- no downloads ReaderNext route wiring
- no executor invocation
- no runtime fallback
- no identity reconstruction

## Hard Rules

1. M17.1 is controller-only; no downloads ReaderNext navigation wiring.
2. Downloads open authority must consume only:
   - M14 readiness artifact
   - M17 downloads preflight output
3. Downloads page must pass row context only and must not build `SourceRef` or `ReaderNextOpenRequest`.
4. Downloads page must not parse canonical IDs or derive upstream IDs from local/cache/archive/file paths.
5. `reader_next_enabled` / `reader_next_downloads_enabled` control route selection only, never validation.
6. `blocked` is terminal; no legacy fallback in blocked branch.
7. `legacyExplicit` may call only explicit legacy route.
8. `readerNextEligible` in M17.1 means prepared/diagnostic only; no executor call yet.
9. Diagnostics must be redacted and must not expose raw canonical/upstream/chapter IDs or local/cache/archive/file paths.
10. History/favorites behavior must remain unchanged.

11. Downloads page may pass only row context fields:
    - `recordId`
    - `sourceKey`
    - `downloadSessionId` when present
    - explicit preflight identity reference when already stored
12. Downloads page must not pass local/cache/archive/file path as identity input.
13. `readerNextEligible` in M17.1 must not expose a `ReaderNextOpenRequest`.
14. `readerNextEligible` in M17.1 may expose only a prepared/diagnostic result for later executor wiring.
15. Local/cache/archive/file paths are storage-only and must not affect route identity or prepared decision.

## Controller Contract

Controller output decisions:

- `legacyExplicit`
- `blocked`
- `readerNextEligible` (prepared only in M17.1)

In M17.1, `readerNextEligible` must not expose a `ReaderNextOpenRequest`. It may expose only a prepared/diagnostic result for later executor wiring.

Controller output packet must include:

- `entrypoint=downloads`
- `routeDecision`
- `recordKind=downloads`
- `recordIdRedacted`
- `sourceKey`
- `downloadSessionIdRedacted` when present
- `candidateId` or `observedIdentityFingerprint`
- `currentSourceRefValidationCode`
- `readinessArtifactSchemaVersion`
- `blockedReason`

Controller output packet must not include:

- raw `canonicalComicId`
- raw `upstreamComicRefId`
- raw `chapterRefId`
- raw `localPath` / `cachePath` / `archivePath` / `filename`
- `ReaderNextOpenRequest` payload
- raw URL, headers, cookies, or tokens

## Tasks

| Task ID   | Deliverable                                                                         | Verification              |
| --------- | ----------------------------------------------------------------------------------- | ------------------------- |
| M17.1-T1  | downloads cutover controller consumes only M14+M17 authority                        | controller test           |
| M17.1-T2  | downloads route decision packet contract (redacted)                                 | diagnostic test           |
| M17.1-T3  | blocked terminal policy (no fallback)                                               | controller test           |
| M17.1-T4  | legacyExplicit path contract                                                        | controller test           |
| M17.1-T5  | eligible path is prepared only (no executor call)                                   | controller/widget test    |
| M17.1-T6  | authority guard: downloads page no `SourceRef`/`ReaderNextOpenRequest` construction | grep-backed test          |
| M17.1-T7  | authority guard: no downloads ReaderNext runtime/presentation route wiring          | grep-backed test          |
| M17.1-T8  | regression guard: history/favorites controller/route behavior unchanged             | authority/regression test |
| M17.1-T9  | local/cache/archive/file path changes do not affect prepared identity decision      | controller test           |
| M17.1-T10 | eligible prepared output does not expose `ReaderNextOpenRequest`                    | controller test           |

## Acceptance Tests

```dart
test('downloads controller uses only M14 readiness + M17 preflight', () {
  // assert no external authority inputs
});

test('downloads legacyExplicit path calls explicit legacy route only', () async {
  // expect legacy called once, blocked/executor zero
});

test('downloads blocked path is terminal', () async {
  // expect blocked called once, legacy/executor zero
});

test('downloads eligible path is prepared only in M17.1', () async {
  // expect decision=readerNextEligible
  // expect no executor callback in this milestone
});

test('downloads eligible prepared output does not expose ReaderNextOpenRequest', () async {
  // expect decision=readerNextEligible
  // expect prepared/diagnostic result only
  // expect no ReaderNextOpenRequest payload
});

test('downloads local path change does not change prepared identity decision', () {
  // same explicit SourceRef and row identity
  // different local/cache/archive paths
  // expect same candidate/prepared decision
});

test('downloads diagnostics are redacted', () {
  // assert packet includes redacted/hash fields
  // assert packet excludes raw canonical/upstream/chapter/path fields
});

test('downloads page does not build identity or route request', () async {
  // grep downloads pages
  // no SourceRef.
  // no ReaderNextOpenRequest(
  // no upstream parsing from local/cache/archive/file path
});
```

## Authority Guards

```bash
rg -n "ReaderNextOpenRequest\\(|SourceRef\\.|upstreamComicRefId|chapterRefId|fromLegacyRemote|open.*ReaderNext|route.*ReaderNext" \
  lib/pages/downloading_page.dart lib/pages/local_comics_page.dart \
  -g '!*.g.dart'

rg -n "features/reader_next/(runtime|presentation)|ReaderNext.*Page|ReaderNext.*Screen|ReaderNextOpenBridge|OpenReaderController|ReaderNext.*Executor" \
  lib/pages/downloading_page.dart lib/pages/local_comics_page.dart \
  -g '!*.g.dart'

rg -n "downloads_route_readiness_preflight|DownloadsRouteReadinessPreflightPolicy|ReaderNextEntrypoint\\.downloads" \
  lib/pages/history_page.dart lib/pages/favorites lib/features/reader_next/bridge/history_route_cutover_controller.dart lib/features/reader_next/bridge/favorites_route_cutover_controller.dart \
  -g '!*.g.dart'
```

This guard intentionally targets open-reader identity construction. It must not fail solely on unrelated downloads status/helper code that mentions canonical IDs without constructing a ReaderNext route request.

Expected:

- no downloads page ReaderNext route wiring
- no downloads page identity construction
- no raw upstream derivation from storage paths
- no cross-entrypoint contamination into history/favorites

## Verification Commands

```bash
flutter test test/features/reader_next/bridge/*downloads*
flutter test test/features/reader_next/runtime/*authority*
dart analyze lib/features/reader_next/bridge lib/features/reader_next/preflight lib/pages/downloading_page.dart lib/pages/local_comics_page.dart test/features/reader_next
git diff --check
```

## M17.1 Closeout Evidence

M17.1 completed as downloads controller-only cutover contract.

Verified:

- downloads controller has `legacyExplicit`, `blocked`, and `readerNextEligible` decisions
- `legacyExplicit` calls explicit legacy callback only
- `blocked` is terminal and does not call legacy fallback
- `readerNextEligible` is prepared-only in M17.1 and does not call executor
- diagnostics are redacted and include record/session/candidate/fingerprint, validation/schema, and blocked reason fields
- downloads ReaderNext route/executor wiring was not added
- M17 preflight lanes remain readiness/preflight only

Final verification:

1. `flutter test test/features/reader_next/bridge/*downloads*`
   - Result: All tests passed (+5)
2. `flutter test test/features/reader_next/runtime/*authority*`
   - Result: All tests passed (+19)
3. `dart analyze lib/features/reader_next/bridge lib/features/reader_next/preflight lib/pages/downloading_page.dart lib/pages/local_comics_page.dart test/features/reader_next`
   - Result: No issues found
4. `git diff --check`
   - Result: clean, no output

## Exit Criteria

- controller-only downloads cutover contract implemented
- no downloads route/executor wiring added
- blocked path terminal and no fallback
- legacyExplicit path explicit only
- eligible path prepared-only in this milestone
- no `ReaderNextOpenRequest` is exposed from downloads controller in M17.1
- local/cache/archive/file paths are storage-only and do not affect route decision
- diagnostics redacted by contract
- history/favorites behavior unchanged
