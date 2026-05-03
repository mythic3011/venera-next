# M12 History/Favorites Identity Backfill Preflight

Goal: audit whether history/favorites entries can produce valid `ReaderNextOpenRequest` without guessing identity fields.

Scope boundary:
- Preflight only.
- No runtime mutation.
- No UI route enablement for history/favorites.

## Hard Rules

1. No runtime fallback.
2. No reconstructing `upstreamComicRefId` from canonical ID by string split.
3. No opening ReaderNext from history/favorites until backfill report proves valid `SourceRef` coverage.
4. Invalid/missing `SourceRef` rows produce diagnostics only.
5. Backfill is offline/preflight first, not runtime mutation.
6. Scanner may validate existing explicit identity fields only.
   It must not infer `upstreamComicRefId` from `recordId`, title, URL, `sourceKey`, or `canonicalComicId`.

## Task Table

| Task ID | Deliverable | Verification |
| --- | --- | --- |
| M12-T1 | add identity coverage scanner for history/favorites records | scanner unit test |
| M12-T2 | report counts: valid SourceRef, missing SourceRef, malformed SourceRef, canonical-leak-as-upstream | report fixture test |
| M12-T3 | add dry-run remediation classification model (no DB writes) | model/service test |
| M12-T4 | add guard test proving history/favorites still cannot open ReaderNext directly | grep/authority-backed test |
| M12-T5 | add fixture tests for old records with missing/malformed identity | fixture matrix test |
| M12-T6 | lock `IdentityCoverageReport.toJson()` fields and enum wire values | `flutter test test/features/reader_next/preflight/history_favorites_identity_preflight_schema_test.dart` |

## Suggested Diagnostics Schema

- `recordKind`: `history | favorites`
- `recordId`
- `sourceKey`
- `hasSourceRef`
- `sourceRefValidationCode`: `valid | missing | malformed | canonicalLeakAsUpstream`
- `canonicalComicIdRedacted`
- `upstreamComicRefIdRedacted`
- `chapterRefIdRedacted`
- `proposalAction`:
  - `none`
  - `eligibleForFutureExplicitBackfill`
  - `requiresUserReopenFromDetail`
  - `requiresLegacyImporterData`
  - `blockedMalformedIdentity`

## Scanner Rule Table

| Input State | Scanner Decision |
| --- | --- |
| valid SourceRef present | valid |
| SourceRef missing | missing |
| SourceRef upstream starts with `remote:` | canonicalLeakAsUpstream |
| SourceRef sourceKey empty/unknown | malformed |
| only recordId/sourceKey exists | missing, not candidate |
| canonicalComicId exists but no upstream ref | missing, not candidate |

Rule constraint:
- `eligibleForFutureExplicitBackfill` is allowed only when a validated explicit `SourceRef` snapshot exists.
- Rows with only `recordId`, `sourceKey`, or `canonicalComicId` must never be marked eligible.
- `requiresLegacyImporterData` is allowed only when the scanner can prove an explicit legacy identity snapshot exists in importer-owned data, but it is not yet available in the current history/favorites row.
- `requiresLegacyImporterData` must not be used for rows that merely have `recordId/sourceKey`.

## Additional Authority Guard

M12 scanner/import-preflight code must not import:
- `lib/features/reader_next/presentation/*`
- `ReaderNextOpenBridge`
- `ReaderNextOpenRequest`

Reason:
- M12 only measures whether history/favorites records have enough explicit identity.
- It must not become an alternate open-reader path.

## Acceptance Tests

```dart
test('scanner does not infer upstream id from recordId even when it looks valid', () {
  final record = IdentityCoverageInput.history(
    recordId: '646922',
    sourceKey: 'nhentai',
    canonicalComicId: 'remote:nhentai:646922',
    sourceRef: null,
  );
  final result = scanner.scan(record);
  expect(result.sourceRefValidationCode, SourceRefValidationCode.missing);
  expect(result.proposalAction, RemediationAction.requiresUserReopenFromDetail);
});

test('scanner classifies canonical id inside upstream field as canonical leak', () {
  final record = IdentityCoverageInput.favorite(
    recordId: 'fav-1',
    sourceKey: 'nhentai',
    sourceRef: ExplicitSourceRefSnapshot(
      sourceKey: 'nhentai',
      upstreamComicRefId: 'remote:nhentai:646922',
      chapterRefId: '1',
    ),
  );
  final result = scanner.scan(record);
  expect(
    result.sourceRefValidationCode,
    SourceRefValidationCode.canonicalLeakAsUpstream,
  );
  expect(result.proposalAction, RemediationAction.blockedMalformedIdentity);
});

test('history favorites preflight does not import ReaderNext open path', () async {
  final files = Directory('lib/features/reader_next')
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.contains('/backfill/') || file.path.contains('/preflight/'));
  for (final file in files) {
    final content = await file.readAsString();
    expect(content, isNot(contains('ReaderNextOpenBridge')));
    expect(content, isNot(contains('ReaderNextOpenRequest')));
    expect(content, isNot(contains('/presentation/')));
  }
});
```

## Exit Criteria

- M12-T1..T6 all green.
- Backfill report artifact generated with identity coverage counts.
- No database mutation in dry-run mode.
- No history/favorites UI route opens ReaderNext.
- No fallback path introduced for invalid/missing identity rows.

## Report Artifact Rules

- Report must include `dryRun: true`.
- Report must include aggregate counts and per-record diagnostics only.
- Report must not include SQL update statements, mutation commands, or executable migration steps.
- Report may include human-readable next-step recommendations.

Exit criteria addendum:
- Backfill report artifact must be explicitly labeled `dryRun: true` and must not contain executable mutation instructions.
