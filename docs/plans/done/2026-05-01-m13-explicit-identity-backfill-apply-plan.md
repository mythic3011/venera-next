# M13 Explicit Identity Backfill Apply Plan

Goal: apply only validated explicit `SourceRef` snapshots into canonical history/favorites identity storage.

Scope boundary:
- Apply lane only.
- No runtime identity guessing.
- No history/favorites ReaderNext route enablement in this milestone.

## Hard Rules

1. Apply input must be generated from M12 report.
2. Only `valid` + `eligibleForFutureExplicitBackfill` rows may be applied.
3. `missing`, `malformed`, `canonicalLeakAsUpstream` rows must never be mutated.
4. No deriving upstream ID from `recordId` / `sourceKey` / `canonicalComicId`.
5. Apply mode must require backup + dry-run artifact hash.
6. Apply must be transactional and resumable.
7. History/favorites ReaderNext route remains disabled until post-apply verification passes.
8. Favorites candidates must include folder-level row identity; `recordId` alone is insufficient.
9. Apply must be compare-and-set using observed identity fingerprint from M12 scan.
10. Resume checkpoint must use deterministic candidate IDs, not list index only.
11. Stale rows are skipped with diagnostics, never overwritten.

## Apply Gate (Mandatory)

Backfill apply is allowed only if all conditions are true:
- `report.dryRun == true`
- report schema version matches current M13 expected version
- every apply candidate has:
  - `recordKind`
  - `folderName` (required for favorites)
  - `recordId`
  - `sourceKey`
  - validated explicit `SourceRef`
  - `canonicalComicId`
  - `upstreamComicRefId`
  - `chapterRefId`
- zero candidates contain `upstreamComicRefId` starting with `remote:`

Gate principle:
- M13 gate validates candidate legality, not overall coverage percentage.
- Coverage threshold is deferred to M14 route-enable decision.

## Task Table

| Task ID | Deliverable | Verification |
| --- | --- | --- |
| M13-T1 | `BackfillApplyPlan` model: derive apply candidates from M12 report | unit test for candidate projection |
| M13-T2 | gate validator: reject stale schema, malformed candidates, non-dry-run report | gate validation test matrix |
| M13-T3 | transactional apply sink interface + in-memory sink test double | sink contract tests |
| M13-T4 | apply execution service: dry-run hash check, backup id requirement, checkpoint/resume | execution tests (resume + failure + idempotency) |
| M13-T5 | post-apply verifier: re-scan applied rows and assert `valid` state | verifier tests |
| M13-T6 | authority guard: history/favorites still cannot open ReaderNext directly | grep/authority-backed test across `lib/pages`, `lib/foundation`, `lib/components` |

## Data/Contract Requirements

- `BackfillApplyPlan` must carry:
  - `reportSchemaVersion`
  - `dryRunArtifactHash`
  - `backupId`
  - candidate list
  - checkpoint cursor
- Candidate payload must include explicit identity fields only.
- Candidate payload must include immutable source row pointer:
  - `recordKind`
  - `folderName` (required for favorites rows)
  - `recordId`
  - `sourceKey`
- Candidate payload must include:
  - `observedIdentityFingerprint` (captured during M12 scan)
  - deterministic `candidateId = hash(recordKind, folderName, recordId, sourceKey, canonicalComicId, upstreamComicRefId, chapterRefId)`
- Plan/output artifacts must be deterministic and auditable.

## Failure Handling

- Any gate failure aborts before mutation starts.
- Partial apply must persist checkpoint and stop safely.
- Resume path must re-validate artifact hash and schema before continuing.
- Apply writes must be compare-and-set:
  - apply only if `currentRowIdentityFingerprint == observedIdentityFingerprint`
  - otherwise skip as `STALE_ROW` and emit diagnostics

## M13-T4 Acceptance Test

```dart
test('apply skips stale row instead of overwriting changed identity', () {
  // M12 observed missing/old identity
  // before apply, sink row changes
  // expect skippedStaleRow count == 1
  // expect no mutation
});
```

## Exit Criteria

- M13-T1..T6 all green.
- Apply path accepts only strict valid candidates and rejects all forbidden classes.
- Transactional apply + resume behavior verified by tests.
- Post-apply verifier confirms applied rows are valid.
- History/favorites ReaderNext route still disabled.
