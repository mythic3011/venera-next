# V2F Import Export Retirement Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make legacy DB files explicit migration inputs only, never active backup/restore runtime authority.

**Architecture:** Split canonical backup/export from legacy import. Canonical export/restore must target `data/venera.db` as the only comic-domain runtime authority. Legacy DB parsing may remain, but only in clearly named import/migration entrypoints. Non comic-domain state such as cookies/appdata/source config is out of scope except where archive labeling must become explicit.

**Tech Stack:** Flutter, zip export/import utilities, legacy parser tests, canonical migration helpers.

---

This slice must remove runtime dependency on the named legacy manager. It may keep legacy parsing/import code only behind explicit migration/import entrypoints.

### Task 1: Split canonical export from legacy import APIs

**Files:**
- Modify: `lib/utils/data.dart`
- Create: `lib/utils/canonical_data_export.dart`
- Create: `lib/utils/legacy_data_import.dart`
- Test: `test/utils/canonical_data_export_test.dart`
- Test: `test/utils/legacy_data_import_test.dart`

**Steps:**
1. Replace the monolithic utility surface with explicit APIs:
   - `exportCanonicalDomainData`
   - `restoreCanonicalDomainData`
   - `importLegacyHistoryDb`
   - `importLegacyLocalDb`
   - `importLegacyFavoritesDb`
2. Keep cookie/appdata/comic_source behavior unchanged unless archive labeling needs clarification.
3. Add failing tests for canonical export/restore and legacy import summaries.
4. Run focused tests and commit.

### Task 2: Remove restore-to-runtime behavior for legacy DB files

**Files:**
- Modify: `lib/utils/data.dart`
- Modify: `lib/pages/settings/app.dart`
- Test: `test/utils/canonical_data_export_test.dart`
- Test: `test/utils/legacy_data_import_test.dart`

**Steps:**
1. Remove restore behavior that renames `history.db`, `local.db`, or `local_favorite.db` into active runtime paths.
2. Convert legacy DB inputs into canonical writes only.
3. Return explicit count/skipped/error summaries for malformed or partial input.
4. Run focused tests and commit.

### Task 3: Keep parser compatibility tests while changing runtime contract

**Files:**
- Modify: `test/foundation/db/legacy_history_migration_test.dart`
- Modify: `test/foundation/db/legacy_local_migration_test.dart`
- Modify: `test/utils/legacy_data_import_test.dart`

**Steps:**
1. Keep existing parser coverage that proves old DB files can still be read.
2. Move runtime contract assertions to canonical export/import tests.
3. Add failure-mode tests for malformed legacy input.
4. Run focused tests and commit.

### Acceptance

```bash
flutter test test/foundation/db/legacy_history_migration_test.dart test/foundation/db/legacy_local_migration_test.dart
flutter test test/utils/canonical_data_export_test.dart test/utils/legacy_data_import_test.dart
flutter analyze
rg "local\\.db|local_favorite\\.db|history\\.db" lib --glob '!**/legacy_*' --glob '!**/*migration*' --glob '!**/import*'
rg "HistoryManager\\(\\)|LocalManager\\(\\)|LocalFavoritesManager\\(" lib/utils lib/features lib/pages --glob '!**/legacy_*' --glob '!**/*migration*' --glob '!**/import*'
```

### Allowed Remaining Matches After V2F

- legacy import/migration modules
- compatibility tests only
- manager class definitions only if no runtime caller imports them
