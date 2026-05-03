# M21 ReaderNext Release Notes + Operator Rollback Guide

Goal:

- Prepare release-facing documentation for the ReaderNext production cutover lane.
- Document per-entrypoint rollback procedures for operators and reviewers.
- Explain blocked-state behavior without introducing fallback semantics.
- Reference the frozen M20 regression pack as the release gate.

Scope:

- docs only
- no code changes
- no new ReaderNext entrypoints
- no new feature flags
- no route behavior changes
- no identity model changes
- no fallback behavior changes
- no diagnostics schema changes
- no importer/backfill changes

## Hard Rules

1. M21 must be documentation-only.
2. M21 must not change production route behavior.
3. M21 must not introduce new entrypoints.
4. M21 must not introduce new fallback behavior.
5. M21 must not weaken M20 freeze rules.
6. M21 must document that feature flags control route selection only.
7. M21 must document that rollback does not mutate identity/readiness data.
8. M21 must document that ReaderNext blocked decisions do not fallback to legacy.
9. M21 must document that legacy is used only when the relevant entrypoint flag is disabled.
10. M21 must document diagnostics redaction expectations.
11. M21 must reference the M20 regression pack as the required release gate.
12. M21 must state that new entrypoints, fallback changes, or identity semantics changes require a new ADR.

## Release Notes Requirements

The release notes must include:

- ReaderNext cutover is guarded by per-entrypoint feature flags.
- Supported cutover entrypoints:
  - history
  - favorites
  - downloads
- Each entrypoint has an independent rollback flag.
- Eligible ReaderNext opens go through the approved navigation executor.
- Blocked ReaderNext decisions are terminal and do not fallback to legacy.
- Legacy reader route remains available only through explicit flag-off route selection.
- Diagnostics are redacted by default.
- The release is gated by the M20 regression pack.

## Operator Rollback Guide Requirements

The operator guide must include:

| Entrypoint | Flag                            | Rollback Action | Expected Behavior                   |
| ---------- | ------------------------------- | --------------- | ----------------------------------- |
| history    | `reader_next_history_enabled`   | set to `false`  | history uses explicit legacy route  |
| favorites  | `reader_next_favorites_enabled` | set to `false`  | favorites use explicit legacy route |
| downloads  | `reader_next_downloads_enabled` | set to `false`  | downloads use explicit legacy route |

Rollback notes:

- Rollback affects route selection only.
- Rollback does not mutate M14 readiness artifacts.
- Rollback does not mutate M16 favorites preflight state.
- Rollback does not mutate M17 downloads preflight state.
- Rollback does not mutate SourceRef snapshots.
- Rollback does not mutate history/favorites/download rows.
- Rollback does not mutate importer/backfill state.
- Rollback for one entrypoint does not disable the other entrypoints.

## Blocked-State Explanation

The documentation must explain:

- A blocked ReaderNext decision is intentional fail-closed behavior.
- Blocked does not mean the app crashed.
- Blocked means the row did not pass the required identity/readiness checks.
- Blocked rows must not silently fallback to legacy.
- Operators may disable the relevant feature flag to route future opens through explicit legacy.
- Blocked diagnostics should be used to identify missing, malformed, stale, or unsafe identity data.

## Diagnostics / Redaction Notes

The documentation must state:

- Diagnostics are redacted by default.
- Diagnostics may include hashed/redacted record, candidate, fingerprint, route decision, validation code, and blocked reason fields.
- Diagnostics must not expose:
  - raw canonical IDs
  - raw upstream IDs
  - raw chapter IDs
  - local paths
  - cache paths
  - archive paths
  - filenames
  - full URLs
  - cookies
  - headers
  - bearer tokens

## Regression Gate Reference

M21 release docs must reference:

- `docs/plans/2026-05-02-m20-readernext-cutover-freeze-regression-pack.md`

Required release gate:

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

## Tasks

| Task ID | Deliverable                                 | Verification |
| ------- | ------------------------------------------- | ------------ |
| M21-T1  | create engineering release-notes plan       | doc review   |
| M21-T2  | create operator rollback guide              | doc review   |
| M21-T3  | document blocked-state behavior             | doc review   |
| M21-T4  | document diagnostics redaction expectations | doc review   |
| M21-T5  | link M20 regression pack as release gate    | doc review   |
| M21-T6  | add release-readiness checklist             | doc review   |

## Proposed Output Files

M21 should produce:

- `docs/plans/2026-05-02-m21-readernext-release-notes-rollback-guide.md`
- `docs/release/readernext-cutover-rollback-guide.md`

The plan file is for engineering traceability.

The release guide is for operators/reviewers.

## Release-Readiness Checklist

Before release:

- [ ] M20 regression pack passes.
- [ ] Release notes mention per-entrypoint flags.
- [ ] Rollback guide lists history/favorites/downloads flags.
- [ ] Blocked-state behavior is documented as fail-closed.
- [ ] Documentation states no fallback after blocked ReaderNext decision.
- [ ] Diagnostics redaction expectations are documented.
- [ ] New entrypoints/fallback/identity changes are marked as requiring a new ADR.

## Exit Criteria

- M21 release documentation plan exists.
- Operator rollback guide exists or is explicitly listed as next output.
- Release docs explain per-entrypoint flags.
- Release docs explain blocked-state behavior.
- Release docs explain rollback does not mutate identity/readiness data.
- Release docs explain diagnostics redaction.
- Release docs reference the M20 regression pack.
- No code or route semantics are changed.

## M21 Closeout Evidence

M21 completed as release-readiness closeout lane (docs-only).

Established artifact:

- `docs/release/readernext-cutover-rollback-guide.md`

Scope confirmation:

- documentation-only updates
- no runtime code changes
- no route semantics changes
- no fallback semantics changes

### Docs Sanity Check

Command:

```bash
rg -n "fallback|legacy|blocked|reader_next_" docs/release/readernext-cutover-rollback-guide.md
```

Result summary:

- rollback flags for history/favorites/downloads are documented (`reader_next_history_enabled`, `reader_next_favorites_enabled`, `reader_next_downloads_enabled`)
- legacy usage is documented only for explicit flag-off route selection
- blocked behavior is documented as terminal fail-closed
- blocked path explicitly states no fallback to legacy

### PR Closeout Draft

Suggested PR title:

- `Freeze ReaderNext cutover lane and add rollback guide`

Suggested PR summary:

- Freeze ReaderNext cutover after final smoke matrix
- Add M20 regression pack and bugfix-only policy
- Add operator rollback guide for history/favorites/downloads
- Document blocked-state behavior and diagnostics redaction
