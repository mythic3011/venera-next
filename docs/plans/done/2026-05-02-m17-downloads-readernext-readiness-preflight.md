# M17 Downloads ReaderNext Readiness Preflight

Goal:

- Decide whether downloads can safely become a future ReaderNext entrypoint.
- Define a downloads-specific identity/readiness model before any route wiring.
- Keep downloads ReaderNext route disabled in this milestone.

Scope:

- downloads readiness/preflight only
- no downloads production ReaderNext route wiring
- no history/favorites behavior change
- no broad UI cutover
- no fallback
- no identity reconstruction
- no deriving upstream identity from local file paths, cache paths, filenames, or downloaded archive paths

## Hard Rules

1. M17 is readiness/preflight only.
2. M17 must not enable downloads ReaderNext route wiring.
3. Downloads route authority must consume only M14 readiness artifact plus downloads-specific preflight output.
4. Downloads row identity must be explicit and must not be inferred from local path, cache key, filename, title, URL, or canonical ID string split.
5. Downloads identity must include `sourceKey` plus explicit upstream/source references required to reconstruct a safe `SourceRef`.
6. Local file path is storage location only, not remote identity.
7. Missing, malformed, stale, or canonical-leak downloads identity must be blocked.
8. `upstreamComicRefId` must not start with `remote:` and must not contain canonical IDs.
9. Feature flags may control route selection only; they must not bypass downloads preflight validation.
10. Downloads page must not construct `ReaderNextOpenRequest` directly.
11. Downloads page must not construct `SourceRef` directly.
12. Downloads page must not import ReaderNext runtime or presentation screen/page classes.
13. Downloads page must not parse canonical IDs or derive upstream IDs.
14. Diagnostics must be redacted by default.
15. Diagnostics must not expose raw canonical IDs, upstream IDs, chapter IDs, local paths, cache paths, cookies, headers, tokens, or full URLs.
16. History/favorites route behavior must remain unchanged.

## Downloads Identity Model

A downloads preflight input must use explicit identity fields only.

Required fields:

- `recordKind`: `downloads`
- `recordId`
- `sourceKey`
- `canonicalComicId` or redacted canonical identity reference
- explicit `sourceRef` snapshot, containing:
  - `sourceKey`
  - `upstreamComicRefId`
  - `chapterRefId` when chapter/page-specific open is required
- `downloadSessionId` or stable download row id when available
- `observedIdentityFingerprint`

Storage-only fields, if present, must not be used to derive upstream identity:

- local file path
- archive path
- cache path
- thumbnail path
- image file path
- filename
- task title
- source URL

## Downloads Candidate ID Rules

`candidateId` must be deterministic and must include explicit identity fields.

Candidate input must include:

- `recordKind`
- `recordId`
- `sourceKey`
- `canonicalComicId`
- `upstreamComicRefId`
- `chapterRefId` when present
- `downloadSessionId` when present

Candidate input must not use:

- local path
- cache path
- archive path
- filename
- title
- URL

If explicit identity is missing, the row is blocked and no candidate is produced.

## Validation Codes

Downloads preflight must classify each row as one of:

- `valid`
- `missingSourceRef`
- `malformedSourceRef`
- `canonicalLeakAsUpstream`
- `staleIdentity`
- `missingRequiredIdentity`

## Remediation Actions

Allowed actions:

- `none`
- `eligibleForFutureDownloadsRoute`
- `requiresUserReopenFromDetail`
- `requiresLegacyImporterData`
- `blockedMalformedIdentity`
- `blockedStaleIdentity`

Rules:

- `eligibleForFutureDownloadsRoute` is allowed only for current valid explicit identity.
- Rows with only local paths/cache paths/filenames must never be marked eligible.
- `requiresLegacyImporterData` is allowed only when importer-owned explicit identity evidence exists.
- Stale rows must be blocked and must not be overwritten.

## Tasks

| Task ID | Deliverable                                                                             | Verification              |
| ------- | --------------------------------------------------------------------------------------- | ------------------------- |
| M17-T1  | downloads preflight input/model with explicit identity only                             | unit test                 |
| M17-T2  | downloads candidate/fingerprint builder excluding local paths                           | unit test                 |
| M17-T3  | validation matrix for valid/missing/malformed/canonicalLeak/stale rows                  | fixture test              |
| M17-T4  | remediation classification without mutation                                             | service test              |
| M17-T5  | diagnostic packet model with redaction                                                  | diagnostic test           |
| M17-T6  | authority guard: downloads page has no ReaderNext route wiring or identity construction | grep-backed test          |
| M17-T7  | guard: history/favorites behavior unchanged                                             | authority/regression test |

## Acceptance Tests

```dart
test('downloads preflight does not infer upstream id from local path', () {
  // localPath=/downloads/nhentai/646922/chapter-1.cbz
  // sourceKey=nhentai
  // sourceRef=null
  // expect missingSourceRef or missingRequiredIdentity
  // expect not eligible
});

test('downloads candidate id excludes local path and filename', () {
  // same explicit identity, different local path/filename
  // expect same candidateId
});

test('downloads candidate id changes when explicit upstream identity changes', () {
  // same local file, different upstreamComicRefId
  // expect different candidateId
});

test('downloads classifies canonical id inside upstream field as canonical leak', () {
  // upstreamComicRefId=remote:nhentai:646922
  // expect canonicalLeakAsUpstream
  // expect blockedMalformedIdentity
});

test('downloads stale identity is blocked even when SourceRef shape is valid', () {
  // observed fingerprint differs from current fingerprint
  // expect staleIdentity
  // expect blockedStaleIdentity
});

test('downloads diagnostic packet is redacted', () {
  // include raw local path, canonical id, upstream id, chapter id in input
  // expect packet excludes raw values
  // expect redacted/hash fields only
});

test('downloads page does not build ReaderNext identity or route request', () async {
  // grep downloads page files
  // expect no ReaderNextOpenRequest(
  // expect no SourceRef.
  // expect no ReaderNext runtime/presentation imports
  // expect no upstream id parsing from path/title/url
});
```

## Diagnostic Packet Contract

Each downloads preflight diagnostic must include:

- `recordKind`: `downloads`
- `recordIdHash` or redacted record id
- `sourceKey`
- `downloadSessionIdHash` when present
- `candidateId` or `observedIdentityFingerprint` when present
- `currentSourceRefValidationCode`
- `readinessArtifactSchemaVersion`
- `preflightDecision`: `blocked | eligibleForFutureDownloadsRoute`
- `blockedReason`

The packet must not include:

- raw `canonicalComicId`
- raw `upstreamComicRefId`
- raw `chapterRefId`
- raw local file path
- raw cache path
- raw archive path
- raw filename
- raw source URL
- raw cookies
- raw request headers
- bearer tokens

## Authority Guards

Required guard coverage:

- downloads pages must not construct `ReaderNextOpenRequest`.
- downloads pages must not construct `SourceRef`.
- downloads pages must not import ReaderNext runtime.
- downloads pages must not import ReaderNext presentation screen/page classes.
- downloads pages must not parse local paths/cache paths/filenames into upstream IDs.
- downloads pages must not reference ReaderNext bridge/controller/executor classes in M17.
- history/favorites route wiring remains unchanged.

Suggested guard commands:

```bash
rg -n "ReaderNextOpenRequest\\(|SourceRef\\.|upstreamComicRefId|fromLegacyRemote|features/reader_next/(runtime|presentation)" \
  lib/pages/downloads lib/pages/local_comics_page.dart \
  -g '!*.g.dart'

rg -n "ReaderNextOpenBridge|OpenReaderController|ReaderNextHistoryOpenExecutor|ReaderNextNavigationExecutor|FavoritesReaderNext|DownloadsReaderNext" \
  lib/pages/downloads lib/pages/local_comics_page.dart \
  -g '!*.g.dart'

rg -n "localPath|cachePath|archivePath|filename|fileName" \
  lib/features/reader_next/preflight lib/pages/downloads \
  -g '!*.g.dart'
```

Expected:

- no downloads ReaderNext route wiring.
- no downloads page identity construction.
- no downloads page ReaderNext runtime/presentation imports.
- no upstream identity derived from local path/cache path/archive path/filename.

## Verification Commands

```bash
flutter test test/features/reader_next/preflight/downloads_route_readiness_preflight_test.dart
flutter test test/features/reader_next/runtime/*authority*
dart analyze lib/features/reader_next/preflight test/features/reader_next/preflight test/features/reader_next/runtime
git diff --check
```

## M17 Closeout Evidence

M17 completed as downloads readiness/preflight only.

Verified:

- downloads preflight uses explicit identity only
- local/cache/archive paths and filenames are never used to derive upstream identity
- deterministic `candidateId` uses explicit identity fields only
- valid/missing/canonicalLeak/stale/missingRequiredIdentity rows are classified explicitly
- stale identity is blocked
- diagnostics are redacted and do not expose raw canonical/upstream/chapter/path/url values
- downloads pages have no ReaderNext route wiring
- history/favorites behavior remains unchanged

Final verification:

1. `flutter test test/features/reader_next/preflight/downloads_route_readiness_preflight_test.dart`
   - Result: All tests passed (+8)
2. `flutter test test/features/reader_next/runtime/*authority*`
   - Result: All tests passed (+19)
3. `dart analyze lib/features/reader_next/preflight test/features/reader_next/preflight test/features/reader_next/runtime`
   - Result: No issues found
4. `git diff --check`
   - Result: clean, no output

## Exit Criteria

- downloads preflight model uses explicit identity only.
- local/cache/archive/file paths are never used to derive upstream identity.
- valid/missing/malformed/canonicalLeak/stale rows are classified explicitly.
- stale rows are blocked.
- diagnostics are redacted by default.
- no downloads ReaderNext route wiring is introduced.
- history/favorites behavior remains unchanged.
