# M16 Favorites ReaderNext Route Cutover Preflight

Goal:

- decide whether favorites can safely become the next ReaderNext entrypoint
- do not enable favorites route yet

Scope:

- favorites preflight only
- no production favorites ReaderNext route wiring
- no downloads route wiring
- no fallback
- no identity reconstruction

## Hard Rules

1. Favorites route authority must consume only M14 readiness artifact.
2. Favorites row identity must include `folderName + recordId + sourceKey`.
3. Favorites without `folderName` are always blocked.
4. Duplicate favorite rows must be treated independently.
5. Move/copy/reorder must not silently reuse stale SourceRef identity.
6. No favorites page may construct `ReaderNextOpenRequest` directly.
7. No favorites page may import ReaderNext runtime or presentation screen.
8. Feature flag must not bypass per-row current validation.
9. Blocked favorites rows must not fallback to legacy reader.
10. Downloads remain disabled.
11. Favorites `candidateId` and `observedIdentityFingerprint` must include `folderName`; they must not degrade to `recordId + sourceKey`.
12. Stale or unknown M14 readiness artifact schema must block favorites.
13. Favorites diagnostics must include folder-scoped identity fields and redacted record id.
14. Favorites preflight must not reuse history candidate/fingerprint builders unless `folderName` is a required input.

## Tasks

| Task ID | Deliverable                                              | Verification     |
| ------- | -------------------------------------------------------- | ---------------- |
| M16-T1  | favorites route input model using folder-scoped identity | unit test        |
| M16-T2  | favorites readiness policy consuming M14 only            | policy test      |
| M16-T3  | duplicate-folder row matrix                              | fixture test     |
| M16-T4  | stale row after move/copy/reorder blocked                | policy test      |
| M16-T5  | blocked diagnostics for favorites rows                   | diagnostic test  |
| M16-T6  | authority guard: no favorites route wiring yet           | grep-backed test |

## Acceptance Tests

```dart
test('same favorite recordId in different folders produces distinct candidate ids', () {
  // folder=A, recordId=646922
  // folder=B, recordId=646922
  // expect candidateId differs
});

test('favorite without folderName is always blocked', () {
  // recordKind=favorites, folderName=null
  // expect blocked
});

test('move or copy stale fingerprint blocks route even if SourceRef shape is valid', () {
  // observed fingerprint from old folder/row
  // current row changed
  // expect blocked
});

test('favorites preflight does not enable route wiring', () async {
  // grep favorites pages
  // expect no ReaderNextOpenBridge / executor / ReaderNextOpenRequest
});

test('stale M14 readiness artifact blocks favorites even when favoritesReady is true', () {
  // readinessArtifactSchemaVersion mismatch
  // favoritesReady=true
  // expect blocked
});

test('favorites diagnostic packet includes folderName and redacted record id', () {
  // blocked favorite row
  // expect folderName present
  // expect raw recordId absent
});

test('favorites candidate builder requires folderName', () {
  // attempt candidate build without folderName
  // expect blocked or throws typed boundary error
});
```

## M16 Closeout Evidence

M16 completed as favorites route cutover preflight only.

Verified:

- favorites identity is folder-scoped with `folderName + recordId + sourceKey`
- favorites `candidateId` and `observedIdentityFingerprint` include `folderName`
- favorites without `folderName` are blocked
- duplicate favorite rows across folders are treated independently
- stale row identity after move/copy/reorder is blocked
- stale or unknown M14 readiness artifact schema blocks favorites even when `favoritesReady=true`
- diagnostics include `recordKind=favorites`, `folderName`, redacted record id, `sourceKey`, validation code, and schema version
- no favorites ReaderNext route wiring was introduced

Final verification:

1. `flutter test test/features/reader_next/preflight/favorites_route_cutover_preflight_test.dart test/features/reader_next/preflight`
   - Result: All tests passed (+26)
2. `flutter test test/features/reader_next/runtime/*authority*`
   - Result: All tests passed (+16)
3. `dart analyze lib/features/reader_next/preflight test/features/reader_next/preflight`
   - Result: No issues found
4. `git diff --check`
   - Result: clean, no output

## Exit Criteria

- favorites preflight model is folder-scoped and deterministic
- duplicate folder rows produce distinct candidate/fingerprint values
- missing `folderName` is always blocked
- stale row identity after move/copy/reorder is always blocked
- blocked diagnostics are emitted with typed reasons
- no favorites ReaderNext route wiring is introduced
