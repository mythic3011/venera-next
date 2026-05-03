# M13 Explicit Identity Backfill Apply (Execution Contract)

Goal:

- apply only M12 `valid + eligibleForFutureExplicitBackfill` rows
- require `backupId` + canonical dry-run artifact hash
- transactional compare-and-set apply
- deterministic `candidateId` checkpoint/resume
- post-apply verifier
- authority guard: history/favorites still cannot open ReaderNext directly

Artifact Hash Rule:

- `dryRunArtifactHash` is computed from canonicalized JSON:
  - stable key order
  - stable candidate/report row order (sorted deterministically)
  - no volatile fields (`generatedAt`, file path, machine name)
- resume must recompute the same canonical hash before applying.
- hash input is canonical JSON value, not raw file bytes.

Deterministic Candidate ID:

```text
candidateId = sha256(
  recordKind + '\0' +
  (folderName ?? '') + '\0' +
  recordId + '\0' +
  sourceKey + '\0' +
  canonicalComicId + '\0' +
  upstreamComicRefId + '\0' +
  chapterRefId
)
```

Mandatory Constraints:

1. No UI route enablement.
2. No runtime fallback.
3. No deriving upstream ID from `recordId/sourceKey/canonicalComicId`.
4. No mutation for `missing/malformed/canonicalLeakAsUpstream` rows.
5. Favorites candidates require `folderName`.
6. Compare-and-set only; stale rows skipped as `STALE_ROW`.
7. Checkpoint uses deterministic `candidateId`, not list index.
