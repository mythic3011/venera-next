# V2D Favorites Runtime Migration Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Move favorites runtime authority from `LocalFavoritesManager` / `local_favorite.db` to canonical favorite tables in `data/venera.db`.

**Architecture:** Keep canonical favorites as the only runtime read/write source for pages, detail actions, home sections, and follow-up flows. Preserve legacy favorites code only for explicit import/export/migration and compatibility tests until V2F.

**Tech Stack:** Flutter, `UnifiedComicsStore`, `FavoritesRuntimeRepository`, canonical favorite tests, page boundary tests.

---

This slice must remove runtime dependency on the named legacy manager. It may keep legacy parsing/import code only behind explicit migration/import entrypoints.

### Task 1: Replace runtime repository internals

**Files:**
- Modify: `lib/features/favorites/data/favorites_runtime_repository.dart`
- Modify: `lib/foundation/favorites.dart`
- Test: `test/features/favorites/favorites_runtime_repository_test.dart`

**Steps:**
1. Rebuild `FavoritesRuntimeRepository` internals on canonical favorite tables only.
2. Preserve folder ordering, counts, linked-folder metadata, and `newFavoriteAddTo` behavior.
3. Add failing canonical repository tests for create/delete/rename/order/add/remove/move/copy/batch delete.
4. Run focused tests and commit.

### Task 2: Remove runtime callers from detail/home/follow-up pages

**Files:**
- Modify: `lib/pages/comic_details_page/favorite.dart`
- Modify: `lib/pages/home_page_legacy_sections.dart`
- Modify: `lib/pages/follow_updates_page.dart`
- Modify: `lib/foundation/comic_detail_legacy_bridge.dart`
- Modify: `lib/foundation/follow_updates.dart`
- Test: `test/features/favorites/favorites_runtime_repository_test.dart`
- Test: `test/pages/home_page_test.dart`

**Steps:**
1. Replace runtime imports of `LocalFavoritesManager` and `comic_detail_legacy_bridge` favorite helpers with canonical repository calls.
2. Keep visible UI behavior unchanged.
3. Add boundary tests that fail if `LocalFavoritesManager` or `FavoritesStore` is initialized during a favorites runtime path.
4. Run focused tests and commit.

### Task 3: Downgrade legacy favorites tests to compatibility gates

**Files:**
- Modify: `test/favorites_manager_phase3b_test.dart`
- Modify: `test/favorites_store_phase3b_test.dart`
- Modify: `docs/plans/2026-04-30-v2d-favorites-runtime-migration.md`

**Steps:**
1. Keep legacy tests passing, but stop using them as the primary runtime-authority acceptance gate.
2. Document clearly that they are compatibility-only until V2F.
3. Run the compatibility tests and commit.

### Acceptance

```bash
flutter test test/features/favorites/favorites_runtime_repository_test.dart
flutter test test/pages/home_page_test.dart
flutter analyze
rg "import .*favorites|LocalFavoritesManager\\(" lib/pages
test -d lib/features/favorites && rg "LocalFavoritesManager\\(|local_favorite\\.db" lib/features/favorites || true
test -d lib/features/follow_updates && rg "LocalFavoritesManager\\(|local_favorite\\.db" lib/features/follow_updates || true
test -d lib/foundation/repositories && rg "import .*favorites|LocalFavoritesManager\\(" lib/foundation/repositories || true
```

### Allowed Remaining Matches After V2D

- legacy favorites manager implementation
- explicit favorites import/export/migration code
- compatibility tests only
- class definitions only, with no runtime callers
