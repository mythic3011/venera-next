# V2E Image Favorites Storage Migration Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Move image favorites storage authority away from `HistoryStore` / `history.db` and into canonical tables in `data/venera.db`.

**Architecture:** Add image-favorite canonical tables and a dedicated runtime repository. Keep `ImageFavoriteManager` only as a temporary façade if needed, but runtime pages/providers must migrate to the canonical repository. Do not create a new database file.

**Tech Stack:** Flutter, Drift/SQLite via `UnifiedComicsStore`, image favorite providers, reader runtime boundary tests.

---

This slice must remove runtime dependency on the named legacy manager. It may keep legacy parsing/import code only behind explicit migration/import entrypoints.

### Task 1: Add canonical image-favorite storage and repository

**Files:**
- Modify: `lib/foundation/db/unified_comics_store.dart`
- Create: `lib/features/image_favorites/data/image_favorite_repository.dart`
- Test: `test/features/image_favorites/image_favorite_repository_test.dart`

**Steps:**
1. Add canonical tables/migrations for image favorites inside `data/venera.db`.
2. Add repository methods for load all, search, find, upsert, delete, and compute inputs.
3. Write failing repository tests first, then implement the minimal canonical storage.
4. Run focused tests and commit.

### Task 2: Migrate runtime pages/providers off `ImageFavoriteManager`

**Files:**
- Modify: `lib/pages/image_favorites_page/image_favorites_page.dart`
- Modify: `lib/pages/image_favorites_page/image_favorites_photo_view.dart`
- Modify: `lib/features/reader/presentation/scaffold.dart`
- Modify: `lib/foundation/image_provider/image_favorites_provider.dart`
- Modify: `lib/pages/home_page.dart`
- Test: `test/features/image_favorites/image_favorite_repository_test.dart`
- Test: `test/reader/reader_runtime_authority_test.dart`

**Steps:**
1. Switch page/provider/runtime imports to the new canonical repository.
2. Keep visible UI and summary behavior unchanged.
3. Add boundary tests that fail if `HistoryManager` or `HistoryStore` is initialized during image-favorites runtime paths.
4. Run focused tests and commit.

### Task 3: Reduce `ImageFavoriteManager` to compatibility façade only

**Files:**
- Modify: `lib/foundation/image_favorites.dart`
- Modify: `lib/utils/data.dart`
- Test: `test/features/image_favorites/image_favorite_repository_test.dart`

**Steps:**
1. Keep `ImageFavoriteManager` only as a compatibility wrapper if any remaining migration path still needs it.
2. Remove runtime ownership from `history.db`.
3. Ensure import/migration code remains explicit and out-of-band.
4. Run focused tests and commit.

### Acceptance

```bash
flutter test test/features/image_favorites/image_favorite_repository_test.dart
flutter test test/reader/reader_runtime_authority_test.dart
flutter analyze
test -d lib/features/image_favorites && rg "ImageFavoriteManager\\(" lib/features/image_favorites || true
rg "ImageFavoriteManager\\(" lib/pages
test -f lib/foundation/image_favorites.dart && rg "HistoryManager\\(\\)|HistoryStore|history\\.db" lib/foundation/image_favorites.dart || true
test -d lib/foundation/image_provider && rg "HistoryManager\\(\\)|HistoryStore|history\\.db" lib/foundation/image_provider || true
```

### Allowed Remaining Matches After V2E

- `ImageFavoriteManager` façade internals only
- explicit legacy history/image-favorite migration code
- compatibility tests only
- class definitions only, with no runtime callers
