# V2C Local Runtime Metadata Migration Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Move local library runtime metadata reads and writes from `LocalManager` / `local.db` to canonical repositories backed by `data/venera.db`, while keeping file storage on disk unchanged.

**Architecture:** Treat local comic metadata and download-completion metadata as canonical runtime state. Keep `LocalManager` available only for explicit import/conversion and legacy file-management helpers that are not yet migrated. Split queue/task runtime from metadata runtime so this slice stays reviewable.

**Tech Stack:** Flutter, `UnifiedComicsStore`, `LocalLibraryRepository`, reader runtime tests, existing local file utilities.

---

This slice must remove runtime dependency on `local.db` for local-library metadata. It may keep legacy parsing/import code only behind explicit migration/import entrypoints.

### Task 1: Freeze scope and split queue authority from metadata authority

**Files:**
- Modify: `docs/plans/2026-04-30-v2c-local-download-runtime-migration.md`
- Modify: `lib/features/downloads/data/download_queue_repository.dart`
- Test: `test/reader/reader_runtime_authority_test.dart`

**Steps:**
1. Keep download queue/file task runtime out of this slice unless a caller only needs canonical metadata.
2. Add a repository boundary or TODO contract so `DownloadQueueRepository` is explicitly out-of-scope for this plan’s acceptance grep.
3. Add a focused boundary test proving local/downloaded status runtime can be validated without initializing `LocalManager`.
4. Run the focused test and commit the scope guard separately.

### Task 2: Add canonical local runtime repository surface

**Files:**
- Modify: `lib/foundation/repositories/local_library_repository.dart`
- Create: `lib/features/local_library/data/local_library_runtime_repository.dart`
- Test: `test/features/local_library/local_library_runtime_repository_test.dart`

**Steps:**
1. Add a runtime-facing canonical repository for recent list, count, search, sort, chapter/page status, cover path, and download presence.
2. Keep the repository read-only first, backed only by canonical tables.
3. Add failing tests for each runtime query surface before wiring callers.
4. Run focused tests and commit.

### Task 3: Switch local library pages and reader local status

**Files:**
- Modify: `lib/pages/local_comics_page.dart`
- Modify: `lib/pages/home_page_legacy_sections.dart`
- Modify: `lib/features/reader/presentation/images.dart`
- Modify: `lib/features/reader/presentation/chapters.dart`
- Test: `test/pages/local_comics_page_data_boundary_test.dart`
- Test: `test/reader/reader_runtime_authority_test.dart`

**Steps:**
1. Replace runtime metadata reads from `LocalManager` with canonical repository calls.
2. Handle missing canonical rows as absent/not-downloaded without falling back to `local.db`.
3. Add/extend page boundary tests that fail if `LocalManager` or `local.db` is initialized on the runtime path under test.
4. Run focused tests and commit.

### Task 4: Canonicalize download completion metadata writes

**Files:**
- Modify: `lib/network/download.dart`
- Modify: `lib/foundation/db/local_comic_sync.dart`
- Modify: `lib/features/downloads/data/download_queue_repository.dart`
- Test: `test/reader/reader_runtime_authority_test.dart`
- Test: `test/features/local_library/local_library_runtime_repository_test.dart`

**Steps:**
1. Route download-completion metadata writes into canonical tables after files are created.
2. Keep physical files on disk unchanged.
3. Add tests proving canonical metadata is written and `local.db` is not created for the covered runtime path.
4. Run focused tests and commit.

### Acceptance

```bash
flutter test test/features/local_library/local_library_runtime_repository_test.dart
flutter test test/pages/local_comics_page_data_boundary_test.dart test/reader/reader_runtime_authority_test.dart
flutter analyze
rg "import .*local|LocalManager\\(" lib/pages lib/foundation/reader
test -d lib/features/local_library && rg "LocalManager\\(|local\\.db" lib/features/local_library || true
test -d lib/foundation/repositories && rg "import .*local|LocalManager\\(" lib/foundation/repositories || true
```

### Allowed Remaining Matches After V2C

- `LocalManager` implementation
- explicit import/conversion utilities
- file-only helpers that do not own runtime metadata authority
- queue/task runtime paths that are explicitly deferred to a later slice
