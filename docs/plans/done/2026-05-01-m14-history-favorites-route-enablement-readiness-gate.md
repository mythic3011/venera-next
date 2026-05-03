# M14 History/Favorites/Downloads Route Enablement Readiness Gate

Goal:

- Decide whether history, favorites, and downloads ReaderNext entrypoints are safe to consider for future enablement after M12/M13 identity preflight and apply.

Scope:

- Readiness gate only.
- No broad UI cutover.
- No fallback.
- No identity reconstruction.
- No route enablement for history, favorites, or downloads in this milestone.

## Hard Rules

1. ReaderNext route enablement requires a valid M14 readiness artifact.
2. M14 readiness must be based on post-apply verifier output or current-row validation output.
3. Only rows with current valid `SourceRef` may be marked `readerNextEligible`.
4. Missing, malformed, stale, or canonical-leak rows remain blocked.
5. Feature flags may control route selection only; they must never relax validation, bypass per-row M14 route decisions, or replace M14 readiness checks.
6. No history, favorites, or downloads route may construct `ReaderNextOpenRequest` directly.
7. No legacy fallback is allowed after a ReaderNext bridge/block failure.
8. Rollout authority must be per-entrypoint, not global.
9. Successful M13 apply is migration evidence only; it is not route authority.

## Task Table

| Task ID | Deliverable                                                                    | Verification        |
| ------- | ------------------------------------------------------------------------------ | ------------------- |
| M14-T1  | Define readiness artifact model from M12/M13 evidence metadata                 | unit test           |
| M14-T2  | Add coverage/eligibility gate for history, favorites, and downloads separately | gate matrix test    |
| M14-T3  | Add blocked-route policy for invalid/stale rows                                | policy/usecase test |
| M14-T4  | Add authority guard proving history/favorites/downloads remain bridge-only     | grep-backed test    |
| M14-T5  | Add dry-run route decision packet for each attempted open                      | diagnostic test     |
| M14-T6  | Add approved entrypoint allowlist, initially disabled                          | authority test      |

## Gate Decision Model

Gate output must support independent readiness decisions:

- `historyReady=false`
- `favoritesReady=false`
- `downloadsReady=false`
- per-entrypoint readiness allow decisions for history, favorites, and downloads independently

These values are readiness signals only. They are not production route switches.
The gate must be explicit and artifact-driven. No entrypoint may become ready because another entrypoint passed.

## Exit Criteria

- Gate can return disabled decisions for all entrypoints or allow each entrypoint independently.
- Invalid rows produce blocked diagnostics, not fallback.
- No route enablement happens unless a later cutover lane consumes a valid M14 readiness artifact.
- UI route switching must not read raw M12/M13 artifacts directly.
- UI route switching may consume only M14 readiness artifacts.

## Critical Safety Note

Coverage percentage is not equal to safety.

Even if most rows are valid, remaining invalid rows are unsafe if any route path:

- falls back silently
- reconstructs identity from `recordId`
- bypasses per-row validation
- treats M13 apply success as route permission

Therefore M14 enforces:

- per-row validity
- per-entrypoint allowlist
- current-row validation
- blocked diagnostics for unsafe rows

M14 must not rely on a single coverage threshold as enablement authority.

## M14 Readiness Authority Statement

M14 is a readiness and quarantine gate only.

It does not enable history, favorites, or downloads ReaderNext routes. A route may be considered only when its own entrypoint-specific readiness artifact proves current explicit `SourceRef` validity.

Successful M13 apply is necessary evidence, but it is not sufficient authority. Current-row validation wins over historical apply output.

Authority boundary:

- M13 report is migration evidence.
- M14 readiness artifact is route authority.
- Later UI cutover lanes may consume M14 readiness artifacts only.

## M14 Artifact Validity Rules

- `readinessArtifactSchemaVersion` must match the current expected schema version.
- Unknown or stale readiness artifact schema disables all history, favorites, and downloads entrypoints.
- M14 readiness may reference M12/M13 artifacts as evidence metadata only.
- M14 route authority must be based on post-apply verifier output or current-row validation output.
- M14 must not consume raw M13 candidate/apply report as route authority.
- A stale current row blocks the route even if previous M13 apply succeeded.

## Per-Row Route Decision Requirements

Each attempted route decision must include:

- `recordKind`
- `folderName` when `recordKind` is `favorites`
- `recordId`
- `sourceKey`
- `candidateId` or `observedIdentityFingerprint`
- `currentSourceRefValidationCode`
- `readinessArtifactSchemaVersion`
- `routeDecision`: `blocked | readerNextEligible`

Favorites rows without `folderName` must always be blocked.

## Route Decision Rules

| Current Row State                                                | Route Decision       |
| ---------------------------------------------------------------- | -------------------- |
| Valid current `SourceRef` and entrypoint allowed by M14 artifact | `readerNextEligible` |
| Missing `SourceRef`                                              | `blocked`            |
| Malformed `SourceRef`                                            | `blocked`            |
| `upstreamComicRefId` contains canonical ID such as `remote:*`    | `blocked`            |
| Current-row fingerprint does not match verified identity         | `blocked`            |
| Readiness artifact schema is stale or unknown                    | `blocked`            |
| Entrypoint not enabled in M14 readiness artifact                 | `blocked`            |

## Authority Guards

M14 guard tests must prove:

- history, favorites, and downloads cannot construct `ReaderNextOpenRequest` directly
- history, favorites, and downloads cannot open ReaderNext presentation routes directly
- unsafe reconstruction patterns such as `SourceRef.remote(... upstreamComicRefId: item.id)` are rejected by grep-backed authority tests
- legacy reader/runtime/component directories do not import ReaderNext runtime or presentation code
- route decision code does not read raw M13 apply output as route authority

## M14 Closeout

M14 completed as readiness/quarantine gate only.

Verified:

- history, favorites, and downloads have independent readiness decisions
- readiness artifact schema version mismatch disables all entrypoints
- stale current-row identity blocks route even when M13 apply report succeeded
- invalid rows produce blocked route diagnostics, not fallback
- route decision authority comes from M14 readiness/current-row validation, not raw M13 apply output
- favorites rows without `folderName` are blocked
- stale, missing, malformed, and canonical-leak rows are blocked
- authority guard blocks unsafe identity reconstruction patterns such as using row/item ID as `upstreamComicRefId`
- no history/favorites/download ReaderNext route enablement was added

Important:

- `historyReady`, `favoritesReady`, and `downloadsReady` are readiness decisions only
- they are not production route switches
- actual route enablement must be handled in a later cutover lane with explicit per-entrypoint wiring and tests

## Final Verification

M14 closeout verification completed.

Commands:

1. `flutter test test/features/reader_next/backfill test/features/reader_next/preflight`
   - Result: All tests passed (+26)
2. `flutter test test/features/reader_next/runtime/*authority*`
   - Result: All tests passed (+12)
3. `dart analyze lib/features/reader_next/preflight lib/features/reader_next/backfill test/features/reader_next`
   - Result: No issues found
4. `git diff --check`
   - Result: clean, no output
