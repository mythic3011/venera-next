# M26.2 Source Repository Registry and Direct Source Install

## Goal

- Make `Settings > Comic Sources` the canonical source management surface.
- Support both repository `index.json` URLs and direct JavaScript source URLs.
- Allow users to add, import, update, remove, reorder, and configure sources from one place.
- Separate repository management, installed source management, and available source discovery.
- Preserve existing installed source runtime behavior and storage authority.

## Problem

Current source management has split ownership.

`Settings > Comic Sources` supports:

- installed source settings
- delete
- reorder
- refresh/update

But it does not clearly support:

- add source
- add repository
- install from direct JS URL
- import local source file
- manage multiple repositories

The current add-source flow is hidden behind another page/modal. This creates an incomplete lifecycle:

```text
Settings can manage installed sources but cannot fully add/discover sources.
Add-source page can install sources but is not the canonical management surface.
```

This is a broken information architecture. Source lifecycle should be owned by one surface.

## Scope

- source repository registry
- direct JavaScript source install
- local source file import
- installed source list view
- available source list view
- source update/check flow wiring
- source remove/reorder/configure flow wiring
- source management UI consolidation
- shared source management controller
- source management command error states

Out of scope:

- no ReaderNext route semantics change
- no ReaderNext render pipeline change
- no appdata migration change
- no cache migration change
- no cookie migration change
- no source JavaScript runtime rewrite
- no source runtime SDK migration
- no source API bypass logic
- no network signing/auth redesign
- no installed source storage migration unless explicitly planned later

## Authority Boundary

M26.2 must not create a second source authority.

- Repository records are authoritative only for repository configuration.
- Repository package metadata is refresh-derived and rebuildable.
- Installed source runtime files, settings, order, and enabled state remain owned by the existing source storage until a separate migration exists.
- `installed_sources` in this plan is a view/adapter model unless inventory proves that no existing authority exists.
- M26.2 must not introduce duplicate installed-source storage.
- The shared controller may expose installed source views by adapting existing storage.
- Repository refresh must never mutate installed source runtime files unless the user explicitly chooses install/update.
- Removing a repository must not remove installed sources by default.

## Legacy Settings Compatibility

Existing `comicSourceListUrl` is a legacy single-repository setting.

- On first repository registry initialization, if no repository records exist, seed one repository from `comicSourceListUrl` when present.
- If `comicSourceListUrl` is missing or empty, seed the built-in default repositories.
- After `source_repositories` exists, repository configuration is read from the repository registry.
- UI writes must go to `source_repositories`, not `comicSourceListUrl`.
- `comicSourceListUrl` may remain for rollback compatibility but must not be the active authority after registry initialization.
- Migration from `comicSourceListUrl` into the repository registry must be idempotent.

## Storage Boundary

- Repository registry metadata must live in the canonical app DB.
- M26.2 must not create a new source registry sidecar DB, JSON file, or cache file.
- `source_repositories` is the active repository configuration authority after registry initialization.
- `source_packages` is derived metadata and may be cleared/rebuilt.
- Installed source runtime files remain under the existing source storage authority.
- Existing installed source settings/order/enabled state must not be migrated into a new table in M26.2.

## Concurrency Boundary

- Repository refresh must be serialized per repository.
- Install/update/remove commands for the same `sourceKey` must be serialized.
- Refresh must not overwrite an installed source unless an explicit update command is confirmed.
- A failed refresh must preserve the previous usable package cache or record a visible failed state.
- Concurrent refresh and install actions must not produce partially installed sources.
- Concurrent update and remove actions for the same source must return a typed conflict/block result.

## Direct JS Validation Boundary

- Direct JS validation must run through the existing source parser sandbox or an equivalent isolated validation path.
- Direct JS validation must not execute untrusted scripts on the UI isolate.
- Validation must enforce timeout and return typed failure on hang/error.
- Script content hash is computed from fetched bytes after successful fetch.
- `content_hash` is optional for repository packages.
- For direct JS installs, content hash is computed from fetched script bytes.
- For repository packages, content hash is used only if provided by repository metadata or computed during install/update.
- Repository refresh must not fetch every source script solely to compute content hashes.

## Hard Rules

1. `Settings > Comic Sources` must become the canonical source management surface.
2. Home/Search source page may remain as a shortcut only.
3. Add source must be available from Settings.
4. Repository `index.json` URL install must be supported.
5. Direct JavaScript source URL install must be supported.
6. Local file import must be supported where existing runtime already supports it.
7. Installed sources and available sources must be visually separated.
8. Repository records must be first-class state, not a transient text field.
9. Multiple repositories must be supported.
10. Repository refresh failure must not delete or mutate installed sources.
11. Repository package metadata must be treated as rebuildable cache.
12. Direct JS install must require explicit user confirmation.
13. Direct JS install must record install origin.
14. Repository install must record repository origin through the existing installed source authority or its adapter.
15. Source key collision must require explicit overwrite/update confirmation.
16. Source install/update/remove must use one shared controller.
17. UI must not duplicate source install/update logic.
18. Source management command errors must render typed visible error state, not silent empty UI.
19. Deep source runtime execution errors are owned by M27, not M26.2.
20. Diagnostics must redact tokens, signatures, cookies, device IDs, pseudo IDs, and auth headers.
21. Public repository URLs may be shown unless they contain secrets.
22. Source script contents must not be dumped into diagnostics by default.
23. Direct JS install must reject non-HTTPS URLs by default, except local/dev override.
24. Direct JS install must reject HTML responses masquerading as JavaScript.
25. Direct JS install must enforce a script size limit.
26. Direct JS install must record a content hash.
27. Direct JS update must validate that the fetched script keeps the same `sourceKey`.
28. Repository index schema must support both the legacy official array shape and the new repository object shape.

## Source Input Types

### 1. Repository Index URL

A repository index points to an `index.json` file containing multiple source package descriptors.

Example:

```text
https://cdn.jsdelivr.net/gh/venera-app/venera-configs@main/index.json
```

Expected use:

- official source catalog
- custom source catalog
- batch source discovery
- update checking
- version comparison
- source install metadata

### 2. Direct JavaScript Source URL

A direct source URL points to a single source script.

Example:

```text
https://example.com/sources/custom_source.js
```

Expected use:

- install one custom source
- developer testing
- private source sharing
- quick source install without maintaining a full repository index

### 3. Local File Import

A local import may point to:

- one source JavaScript file
- one source config package
- one repository index JSON file

## Repository Index Schema

M26.2 must support the existing official legacy shape and a forward-compatible repository object shape.

### Legacy Official Shape

Current official source index may be a raw array:

```json
[
  {
    "name": "拷贝漫画",
    "fileName": "copy_manga.js",
    "key": "copy_manga",
    "version": "1.4.1"
  }
]
```

Compatibility rule:

- Treat the repository name as the configured repository record name.
- Resolve `fileName` relative to the repository index URL.
- Preserve `key`, `name`, `version`, and optional `description`.

### Repository Object Shape

New custom repositories may use an object wrapper:

```json
{
  "schemaVersion": 1,
  "name": "My Source Repository",
  "sources": [
    {
      "key": "custom_source",
      "name": "Custom Source",
      "version": "1.0.0",
      "fileName": "custom_source.js",
      "url": "https://example.com/sources/custom_source.js",
      "description": "Optional source description"
    }
  ]
}
```

Validation rules:

- `sources` must be a list.
- each source must have `key`, `name`, and either `fileName` or `url`.
- `fileName` must resolve under the repository base URL.
- `url` must use HTTPS unless local/dev override is active.
- source keys must be unique within the repository.
- unsupported schema versions must return typed error `REPOSITORY_SCHEMA_UNSUPPORTED`.

## Data Model Direction

### `source_repositories`

Repository records are authoritative for repository configuration only and must be stored in the canonical app DB.

```sql
CREATE TABLE source_repositories (
  id TEXT PRIMARY KEY NOT NULL,
  name TEXT NOT NULL,
  index_url TEXT NOT NULL,
  enabled INTEGER NOT NULL DEFAULT 1,
  user_added INTEGER NOT NULL DEFAULT 1,
  trust_level TEXT NOT NULL DEFAULT 'user',
  last_refresh_at_ms INTEGER,
  last_refresh_status TEXT,
  last_error_code TEXT,
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL,
  CHECK (enabled IN (0, 1)),
  CHECK (user_added IN (0, 1)),
  CHECK (trust_level IN ('official', 'user', 'unknown')),
  CHECK (last_refresh_status IS NULL OR last_refresh_status IN ('success', 'failed', 'never'))
);
```

### `source_packages`

Repository package metadata is refresh-derived and rebuildable. It is not installed source authority.

If stored in DB, it must be safe to clear and rebuild from enabled repositories.

```sql
CREATE TABLE source_packages (
  source_key TEXT NOT NULL,
  repository_id TEXT NOT NULL,
  name TEXT NOT NULL,
  file_name TEXT,
  script_url TEXT,
  available_version TEXT,
  description TEXT,
  content_hash TEXT,
  last_seen_at_ms INTEGER NOT NULL,
  PRIMARY KEY (source_key, repository_id),
  FOREIGN KEY (repository_id) REFERENCES source_repositories(id)
);
```

Required policy:

- package rows may be deleted during refresh reconciliation.
- package rows must not be used as installed-source truth.
- package refresh failure must leave previous package rows or explicit failed state, but must not touch installed sources.
- `content_hash` is optional for repository packages and must not force refresh to download every source script.

### Installed Source View / Adapter

Do not create `installed_sources` as a new authoritative table unless a later migration explicitly moves installed source authority.

M26.2 should first implement this as a view model backed by existing source storage:

```dart
class InstalledSourceView {
  const InstalledSourceView({
    required this.sourceKey,
    required this.name,
    required this.installedVersion,
    required this.installOriginType,
    required this.installOriginRef,
    required this.enabled,
    required this.status,
  });

  final String sourceKey;
  final String name;
  final String? installedVersion;
  final String installOriginType;
  final String? installOriginRef;
  final bool enabled;
  final String status;
}
```

If existing storage cannot record install origin, M26.2 may add origin metadata only after inventory proves the current authority and update path.

## UI Model

`Settings > Comic Sources` should be split into three sections.

### Section A: Repositories

Purpose: manage source catalogs.

Required actions:

- Add repository URL
- Edit repository URL
- Enable/disable repository
- Refresh repository
- Remove repository
- View last refresh status
- View package count

### Section B: Installed Sources

Purpose: manage sources already installed.

Required actions:

- Open source settings
- Reorder
- Check update
- Disable/enable
- Remove
- Show installed version
- Show update available state
- Show command error state

### Section C: Available Sources

Purpose: discover installable sources from enabled repositories.

Required actions:

- Search/filter
- Install
- View version
- View repository origin
- View description
- Show installed/checkmark if already installed

## Add Source Flow

Add Source should offer explicit modes:

1. Add from repository index URL
2. Add from direct JavaScript URL
3. Import local source file
4. Browse enabled repositories

### Repository URL Flow

1. User enters repository index URL.
2. App validates URL scheme.
3. App fetches index.
4. App validates JSON shape.
5. App displays repository summary.
6. User confirms add.
7. Repository is saved.
8. Repository refresh populates available source packages.
9. Refresh lock is released after success or typed failure.

Failure states:

- invalid URL
- non-HTTPS URL without local/dev override
- network failed
- invalid JSON
- missing package descriptors
- duplicate repository
- default repository seed conflict
- unsupported repository schema
- package URL escapes repository base path

### Direct JS URL Flow

1. User enters JS URL.
2. App validates URL scheme.
3. App fetches script metadata or script content.
4. App validates script through the source parser sandbox or equivalent isolated validation path.
5. App rejects HTML/non-JS responses.
6. App enforces script size limit.
7. App validates source script shape.
8. App extracts source key/name/version where possible.
9. App displays warning: remote script will run inside app source runtime.
10. User confirms install.
11. App records install origin as `direct_js` through existing source authority/adapter.
12. App records content hash where supported.
13. Source appears in installed sources.

Failure states:

- invalid URL
- non-HTTPS URL without local/dev override
- fetch failed
- response content type invalid
- script too large
- script validation failed
- script validation timed out
- source key missing
- source key collision
- unsupported source version

### Local File Import Flow

1. User selects local file.
2. App determines file type.
3. If repository index JSON: import as repository.
4. If source JS: install as direct/local source.
5. If unsupported: show typed error.

## Update Semantics

### Repository-backed Source Update

- Compare installed version with available version from the recorded repository origin.
- Fetch script from that repository package.
- Validate source key matches installed source key.
- Require confirmation when update changes source key/name unexpectedly.
- Refresh failure must not mutate installed source.

### Direct JS Source Update

- Fetch from recorded direct JS origin URL.
- Validate fetched script keeps the same source key.
- If source key differs, block with `SOURCE_KEY_MISMATCH`.
- Recompute content hash.
- Apply update only after validation succeeds.

### Local File Source Update

- No automatic remote update unless an origin URL exists.
- UI should show local/manual update state.

## Source Management Controller

Add one shared controller so Settings and Home shortcuts do not duplicate logic.

```dart
abstract interface class SourceManagementController {
  Future<List<SourceRepositoryView>> listRepositories();
  Future<List<InstalledSourceView>> listInstalledSources();
  Future<List<AvailableSourcePackageView>> listAvailablePackages();

  Future<SourceCommandResult> addRepository(String indexUrl);
  Future<SourceCommandResult> refreshRepository(String repositoryId);
  Future<SourceCommandResult> removeRepository(String repositoryId);
  Future<SourceCommandResult> setRepositoryEnabled(String repositoryId, bool enabled);

  Future<SourceCommandResult> installFromRepository({
    required String repositoryId,
    required String sourceKey,
    bool confirmOverwrite = false,
  });

  Future<SourceCommandResult> installFromDirectJsUrl(
    String scriptUrl, {
    bool confirmInstall = false,
    bool confirmOverwrite = false,
  });

  Future<SourceCommandResult> importLocalSourceFile(String filePath);
  Future<SourceCommandResult> updateSource(String sourceKey);
  Future<SourceCommandResult> removeSource(String sourceKey);
  Future<SourceCommandResult> reorderSources(List<String> orderedSourceKeys);
}
```

## Typed Command Results

Do not throw raw exceptions into UI.

```dart
sealed class SourceCommandResult {
  const SourceCommandResult();
}

class SourceCommandSuccess extends SourceCommandResult {
  const SourceCommandSuccess();
}

class SourceCommandBlocked extends SourceCommandResult {
  const SourceCommandBlocked({
    required this.code,
    required this.message,
  });

  final String code;
  final String message;
}

class SourceCommandFailed extends SourceCommandResult {
  const SourceCommandFailed({
    required this.code,
    required this.message,
  });

  final String code;
  final String message;
}
```

Expected codes:

- `REPOSITORY_URL_INVALID`
- `REPOSITORY_URL_INSECURE`
- `REPOSITORY_FETCH_FAILED`
- `REPOSITORY_SCHEMA_INVALID`
- `REPOSITORY_SCHEMA_UNSUPPORTED`
- `REPOSITORY_DUPLICATE`
- `REPOSITORY_PACKAGE_URL_INVALID`
- `SOURCE_SCRIPT_URL_INVALID`
- `SOURCE_SCRIPT_URL_INSECURE`
- `SOURCE_SCRIPT_FETCH_FAILED`
- `SOURCE_SCRIPT_CONTENT_TYPE_INVALID`
- `SOURCE_SCRIPT_TOO_LARGE`
- `SOURCE_SCRIPT_SCHEMA_INVALID`
- `SOURCE_SCRIPT_VALIDATION_TIMEOUT`
- `SOURCE_KEY_MISSING`
- `SOURCE_KEY_COLLISION`
- `SOURCE_KEY_MISMATCH`
- `SOURCE_COMMAND_CONFLICT`
- `SOURCE_INSTALL_BLOCKED`
- `SOURCE_UPDATE_FAILED`
- `SOURCE_REMOVE_FAILED`

## Security Rules

1. Direct JS install must show origin URL before install.
2. Direct JS install must show detected source key/name/version before install when available.
3. Direct JS install must require explicit user confirmation.
4. Installed source must record install origin where existing source authority supports it.
5. Direct JS source must not be silently marked official.
6. Repository source must record repository ID through the existing authority/adapter where supported.
7. Source key collision must require explicit overwrite/update confirmation.
8. Update checks for direct JS sources must only use recorded origin unless user changes it.
9. Source scripts must be validated before install.
10. Source scripts must not be dumped into logs by default.
11. Direct JS install must reject non-HTTPS URLs by default, except local/dev override.
12. Direct JS install must reject HTML/non-JS responses.
13. Direct JS install must enforce a script size limit.
14. Direct JS install must record content hash where supported.
15. Direct JS validation must not execute untrusted scripts on the UI isolate.
16. Direct JS validation must enforce timeout/failure isolation.
17. Repository refresh must not fetch every source script solely to compute hashes.
18. Network diagnostics must redact:
    - authorization
    - cookies
    - device identifiers
    - pseudo IDs
    - signatures
    - timestamps used for auth
    - tokens
19. Repository refresh failure must not mutate installed source runtime.
20. Removing repository must not automatically delete installed sources unless user explicitly asks.

## Migration / Compatibility

Existing source behavior must continue.

Required compatibility:

- existing installed sources remain installed
- existing source settings remain readable
- existing source order remains preserved
- existing built-in default repository URLs may be seeded as default repositories
- existing add-source popup may remain as shortcut
- existing source update logic should be reused, not rewritten
- existing official legacy index array shape must remain supported
- existing `comicSourceListUrl` must seed the first repository registry entry when present
- after repository registry initialization, UI writes must use `source_repositories`

Default repository seeds:

- name: `Official Venera Configs`
- url: `https://cdn.jsdelivr.net/gh/venera-app/venera-configs@main/index.json`
- trustLevel: `official`
- enabled: `true`
- userAdded: `false`

- name: `Mythic Venera Configs`
- url: `https://cdn.jsdelivr.net/gh/mythic3011/venera-configs@main/index.json`
- trustLevel: `official`
- enabled: `true`
- userAdded: `false`

## M26 / M27 Boundary

M26.2 owns source management UX and command routing.

M26.2 does not own deep JavaScript runtime behavior. The following are M27 concerns:

- source runtime SDK
- JavaScript helper APIs
- OpenCC/tag normalization runtime helpers
- mapping raw JavaScript `TypeError`/`ReferenceError` into source runtime typed errors
- API response schema helpers for source scripts

M26.2 may display typed command errors from source management actions. Deep source runtime execution errors should remain covered by M27.

## Implementation Order

### M26.2-A: Inventory

Commands:

```bash
rg -n "add.*source|source.*list|ComicSource|source settings|check update|use config|index.json|venera-configs" lib test
rg -n "copy_manga.js|fileName|sourceKey|version|source.*install|source.*update" lib test
rg -n "Settings.*source|漫畫源|搜索源|Source" lib/pages lib/components
rg -n "source.*order|source.*settings|enabled.*source|delete.*source|remove.*source" lib test
```

Deliverable:

- current source management callsite inventory
- existing installed source authority identification
- existing add/update/delete/reorder command mapping
- source settings persistence mapping
- source order persistence mapping
- current official index shape confirmation

#### M26.2-A Inventory Results (2026-05-02)

##### Callsite Inventory

- Primary source-management surface implementation:
  - `lib/pages/comic_source_page.dart`
- Home shortcut surface:
  - `lib/pages/home_page.dart` (`_ComicSourceWidget` opens `ComicSourcePage`)
- Empty-source detour entrypoints:
  - `lib/pages/search_page.dart`
  - `lib/pages/explore_page.dart`
  - `lib/pages/categories_page.dart`
- Settings source-related UI currently present:
  - `lib/pages/settings/explore_settings.dart` (`Search Sources` selector only)
  - `lib/pages/settings/debug.dart` (ReaderNext/debug flags only)
- Settings currently has no dedicated top-level `Comic Sources` page category.

##### Existing Installed Source Authority

- Runtime installed-source owner:
  - `ComicSourceManager` (`lib/features/sources/comic_source/comic_source.dart`)
- Source script parse/install path:
  - `ComicSourceParser.createAndParse(...)`
  - `ComicSourceManager().add(...)`
- Source update path:
  - `ComicSourcePage.update(...)` (fetch + parse + overwrite + reload)
- Source removal path:
  - `ComicSourceManager().remove(...)` + source file delete

##### Command Mapping (Current)

- Add source from direct URL:
  - `_BodyState.handleAddSource` in `comic_source_page.dart`
- Import source from local JS file:
  - `_BodyState._selectFile` in `comic_source_page.dart`
- Add/install from repository package list:
  - `_ComicSourceList` in `comic_source_page.dart`
- Check updates:
  - `ComicSourcePage.checkComicSourceUpdate()` + `_CheckUpdatesButton`
- Reorder installed sources:
  - `_SliverComicSource` drag path in `comic_source_page.dart`
- Per-source settings:
  - `_SourceSettings` in `comic_source_page.dart`

##### Persistence Mapping

- Repository URL state (single URL today):
  - `appdata.settings['comicSourceListUrl']`
- Installed source scripts:
  - per-source files under app data `comic_source/`
- Available update map:
  - `ComicSourceManager().availableUpdates`
- Search/explore/category/favorites linkage:
  - `_validatePages()` and `_addAllPagesWithComicSource(...)` in `comic_source_page.dart`

##### Source Order Persistence Mapping

- Current source order is managed through `ComicSourceManager` ordering and reorder UI in `comic_source_page.dart`.
- No first-class repository registry/order model exists yet.

##### Official Index Shape Confirmation

- Current code assumes list/array payload shape for index entries in `_ComicSourceList` and `checkComicSourceUpdate`.
- M26.2-C must support both legacy array and object schemas via typed parser.

### M26.2-B: Controller Extraction

- Create `SourceManagementController`.
- Move add/update/delete/reorder/import command routing behind controller.
- Keep existing UI behavior unchanged.
- Add unit tests for controller command routing.
- Do not create new installed source authority.

#### M26.2-B Closeout Hazard

- Hazard:
  - source import test path depends on `App.cachePath` global initialization through `FileSelectResult` finalizer behavior.
- Mitigation applied in B-lane tests:
  - isolate `App.cachePath` override via `setUp/tearDown` and restore previous value when present.
- Residual limitation:
  - if `App.cachePath` was uninitialized before the test, Dart cannot restore the original uninitialized `late` state after the test.
  - the current fallback only prevents later tests from reading a deleted/invalid path; it must be treated as temporary test harness containment, not a permanent design.
- Follow-up (M26.2-C+):
  - isolate `FileSelectResult` temp/cache dependency behind an explicit testable path provider to remove hidden global coupling.

#### M26.2-B Acceptance Boundary

- Controller extraction only.
- Repository registry is not completed in B-lane.
- Direct JS hardening is not completed in B-lane.
- Settings UI consolidation is not completed in B-lane.

### M26.2-C: Repository Registry

- Add repository model/store.
- Seed official repository.
- Migrate legacy `comicSourceListUrl` into the first repository registry entry when present.
- Store repository metadata in the canonical app DB only.
- Support add/remove/enable/disable/refresh repository.
- Store last refresh status.
- Parse both legacy array and object repository schemas.
- Do not alter installed sources on refresh failure.
- Serialize refresh per repository.

#### M26.2-C Implementation Stages

##### M26.2-C1: Repository Schema / Store Skeleton

Scope:

- add `source_repositories` table in the canonical app DB
- add `source_packages` table in the canonical app DB
- add repository store adapter
- add package cache store adapter
- no UI change
- no source install/update behavior change
- no direct JS validation change

Required behavior:

- repository records persist in the canonical app DB only
- repository package metadata is refresh-derived and rebuildable
- no source registry sidecar file is created
- installed source authority remains unchanged

Acceptance tests:

```dart
test('repository registry uses canonical app db and does not create sidecar files', () async {});
test('source packages are refresh-derived and rebuildable', () async {});
```

##### M26.2-C2: Legacy `comicSourceListUrl` Seed Migration

Scope:

- seed first repository record from legacy `comicSourceListUrl` when registry is empty
- seed built-in default repositories when legacy setting is missing/empty
- keep legacy setting as rollback artifact only
- no UI writes back to `comicSourceListUrl`

Required behavior:

- seeding is idempotent
- after repository records exist, `source_repositories` is active authority
- legacy setting does not create duplicate repository records
- missing/corrupt setting state falls back to built-in default repositories

Acceptance tests:

```dart
test('legacy comicSourceListUrl migrates into repository registry once', () async {});
test('repository registry seeds built-in default repositories when legacy setting missing', () async {});
test('repository registry seed is idempotent', () async {});
```

##### M26.2-C3: Repository Index Parser

Scope:

- parse legacy official array schema
- parse object `schemaVersion: 1` schema
- resolve `fileName` relative to repository index URL
- validate HTTPS policy for package URLs
- return typed parser errors

Required behavior:

- legacy official array shape remains supported
- object schema remains forward-compatible
- malformed entries do not crash refresh
- unsupported schema version returns `REPOSITORY_SCHEMA_UNSUPPORTED`
- package URL escaping repository base path returns `REPOSITORY_PACKAGE_URL_INVALID`

Acceptance tests:

```dart
test('legacy official array repository schema remains supported', () async {});
test('object repository schema is supported', () async {});
test('unsupported repository schema version returns typed error', () async {});
test('repository package url escaping base path is rejected', () async {});
```

##### M26.2-C4: Repository Refresh Command

Scope:

- add `refreshRepository(repositoryId)` store/controller implementation
- serialize refresh per repository
- update `source_packages` as rebuildable cache
- preserve previous usable package cache on refresh failure or record visible failed state
- do not mutate installed sources

Required behavior:

- refresh success updates package cache and repository status
- refresh failure records typed status/error
- refresh failure does not delete or mutate installed sources
- concurrent refresh for same repository is serialized

Acceptance tests:

```dart
test('can add repository index url and refresh packages', () async {});
test('repository refresh failure does not delete or mutate installed sources', () async {});
test('repository refresh is serialized per repository and does not corrupt package cache', () async {});
```

##### M26.2-C5: Controller Integration

Scope:

- wire `listRepositories()` to repository store
- wire `listAvailablePackages()` to package cache
- wire `addRepository()` to repository store and typed validation
- wire `refreshRepository()` to refresh command
- keep existing installed-source commands on existing authority
- no Settings UI consolidation yet

Required behavior:

- Home/source shortcut and future Settings UI can call the same controller
- controller returns typed command results
- repository commands do not duplicate installed-source storage

Acceptance tests:

```dart
test('home source shortcut and settings source page use same controller', () async {});
test('invalid repository index url shows typed error', () async {});
test('repository commands do not create duplicate installed source authority', () async {});
```

#### M26.2-C Verification Commands

```bash
flutter test test/features/source_management/source_repository_store_test.dart
flutter test test/features/source_management/source_repository_seed_test.dart
flutter test test/features/source_management/source_repository_schema_test.dart
flutter test test/features/source_management/source_repository_refresh_test.dart
flutter test test/features/source_management/source_management_controller_test.dart
dart analyze lib/features/sources/comic_source lib/foundation/db test/features/source_management
git diff --check
```

#### M26.2-C Exit Criteria

- repository registry tables exist in canonical app DB only
- no source registry sidecar file exists
- legacy `comicSourceListUrl` seeds the registry only once
- missing legacy `comicSourceListUrl` seeds both built-in default repositories
- `source_repositories` becomes active repository authority after initialization
- legacy official array index shape is supported
- object schemaVersion 1 index shape is supported
- repository package metadata is rebuildable cache
- repository refresh is serialized per repository
- repository refresh failure does not mutate installed sources
- shared controller exposes repository list/add/refresh/package listing commands
- no Settings UI consolidation is included in C-lane

### M26.2-D: Direct JS Install

- Add direct JS URL install path.
- Reject insecure URLs by default.
- Reject HTML/non-JS responses.
- Enforce script size limit.
- Validate through parser sandbox or equivalent isolated validation path.
- Enforce validation timeout.
- Validate source script metadata.
- Confirm before install.
- Record origin/content hash where existing source authority supports it.
- Handle source key collision.

#### M26.2-D1: Direct JS Validation Service (Validation-Only)

Scope:

- HTTPS-only validation input path
- reject HTML/non-JS responses
- script size limit
- parser sandbox or equivalent isolated validation path
- timeout enforcement
- extract source key/name/version metadata where possible
- return typed `SourceCommandResult` / typed failure code
- no install write path
- no source enablement path
- no direct JS install button enablement

Acceptance tests:

```dart
test('direct javascript source rejects non https url by default', () async {});
test('direct javascript source rejects html response masquerading as script', () async {});
test('direct javascript source enforces script size limit', () async {});
test('direct javascript validation runs outside ui isolate with timeout', () async {});
```

### M26.2-E: Settings UI Consolidation

- Update `Settings > Comic Sources`.
- Add Repositories section.
- Add Installed Sources section.
- Add Available Sources section.
- Expose Add Source action.
- Expose Import Local File action.
- Expose Check Updates action.
- Keep Home/Search shortcut but route to same controller.

#### M26.2-E Closeout Evidence

Implemented UI consolidation boundaries:

- `ComicSourcePage` now orders source management as:
  1. Repositories
  2. Add / Import Source
  3. Available Sources
  4. Installed Sources
  5. installed source list
- The legacy `_ComicSourceList` entrypoint is no longer exposed from the Add / Import section.
- The UI no longer exposes the legacy `comicSourceListUrl` write flow through the old source-list popup.
- Direct URL / local file import remains visible but is labelled as a trusted-source action.
- Available repository packages are displayed as discovery metadata only.
- Available source install is intentionally disabled with an `Install pending` state until the Direct JS install hardening lane is complete.

Verification:

```bash
dart analyze lib/pages/comic_source_page.dart test/pages/settings_comic_sources_page_test.dart
flutter test test/pages/settings_comic_sources_page_test.dart
```

#### M26.2-E Acceptance Boundary

- E-lane consolidates the source management surface only.
- E-lane does not complete Direct JS install hardening.
- E-lane does not enable repository package installation.
- E-lane does not change installed source runtime authority.
- E-lane does not change ReaderNext, cache, appdata, or cookie semantics.

### M26.2-F: Diagnostics and Command Error State

- Add typed visible UI errors for source management commands.
- Remove silent empty command states.
- Redact sensitive network/source diagnostics.
- Add tests for redaction.
- Do not claim to solve deep JS runtime errors in this milestone.

#### M26.2-F Implementation Stages

##### M26.2-F1: UI Command Result Handling

Scope:

- handle typed command results from repository add/refresh/remove/enable actions
- show visible user-safe error state for blocked/failed command results
- avoid displaying raw exception strings in UI
- keep success feedback lightweight
- no Direct JS install enablement

Required behavior:

- controller `SourceCommandBlocked` and `SourceCommandFailed` map to user-safe text
- raw exception strings are not shown directly to users
- repository command failures are visible through SnackBar or inline error state
- success state does not mask failed repository refresh status

Acceptance tests:

```dart
test('repository command failure renders visible typed error', () async {});
test('repository add invalid url shows user safe typed error', () async {});
```

##### M26.2-F2: Repository Row Status Surface

Scope:

- display `lastRefreshStatus` on repository rows
- display `lastErrorCode` when refresh/add/update actions fail
- show per-repository refresh loading state where practical
- avoid full-page loading for one repository refresh

Required behavior:

- failed repository refresh leaves row visible
- failed repository refresh exposes typed code such as `REPOSITORY_SCHEMA_UNSUPPORTED`
- refresh loading state is scoped to the affected repository where practical
- installed sources are not hidden by repository refresh failure

Acceptance tests:

```dart
test('repository row displays last refresh failure code', () async {});
test('repository refresh failure keeps installed source list visible', () async {});
```

##### M26.2-F3: Diagnostics Redaction Helper

Scope:

- add or reuse source-management diagnostics redaction helper
- redact sensitive request headers and query values before persistence
- redact source command diagnostics before display/logging
- keep raw source script content out of logs by default

Required redaction keys:

- `authorization`
- `cookie`
- `set-cookie`
- `x-auth-signature`
- `x-auth-timestamp`
- `deviceinfo`
- `device`
- `pseudoid`
- `umstring`
- `token`
- `session`
- `password`

Required behavior:

- sensitive headers are redacted case-insensitively
- signed query parameters are redacted
- raw source script content is not persisted by default
- diagnostics keep source key, stage, and typed error code where safe

Acceptance tests:

```dart
test('source diagnostics redact auth headers device identifiers and signatures', () async {});
test('source diagnostics redact signed query parameters', () async {});
test('source diagnostics do not persist raw source script content by default', () async {});
```

##### M26.2-F4: Verification

Commands:

```bash
flutter test test/pages/settings_comic_sources_page_test.dart
flutter test test/features/source_management/source_management_controller_test.dart
flutter test test/features/source_management/source_management_redaction_test.dart
dart analyze lib/pages/comic_source_page.dart lib/features/sources/comic_source test/pages test/features/source_management
git diff --check
```

#### M26.2-F Acceptance Boundary

- F-lane only handles source management command errors and diagnostics redaction.
- F-lane does not enable direct JavaScript package installation.
- F-lane does not validate or execute Direct JS source scripts.
- F-lane does not change installed source authority.
- F-lane does not change ReaderNext, cache, appdata, or cookie semantics.

#### M26.2-F Closeout Evidence

Implemented:

- F1: repository command failures now surface visible typed UI errors (inline + message), avoiding raw exception strings.
- F2: repository rows now show `lastRefreshStatus` and `lastErrorCode`.
- F3: diagnostics redaction helper added for source-management data.
  - headers redacted case-insensitively
  - signed query parameters redacted
  - raw source script content blocked from diagnostics payloads by default
- F1 follow-up: invalid repository URL now returns typed `SourceCommandFailed(code: REPOSITORY_URL_INVALID)`; UI maps typed code instead of Dart exception class.

Files:

- `lib/pages/comic_source_page.dart`
- `lib/features/sources/comic_source/source_management_controller.dart`
- `lib/features/sources/comic_source/source_management_redaction.dart`
- `test/features/source_management/source_management_controller_test.dart`
- `test/features/source_management/source_management_redaction_test.dart`

Verification:

```bash
dart analyze lib/features/sources/comic_source/source_management_controller.dart \
  lib/features/sources/comic_source/source_management_redaction.dart \
  lib/pages/comic_source_page.dart \
  test/features/source_management/source_management_controller_test.dart \
  test/features/source_management/source_management_redaction_test.dart

flutter test test/features/source_management/source_management_controller_test.dart \
  test/features/source_management/source_management_redaction_test.dart
```

## Acceptance Tests

```dart
test('settings comic sources page exposes add source action', () async {});
test('settings comic sources page exposes repository management section', () async {});
test('settings comic sources page separates installed and available sources', () async {});
test('settings comic sources page orders repositories add import available and installed sections', () async {});
test('settings comic sources page does not expose legacy comicSourceListUrl popup entrypoint', () async {});
test('available source install button remains disabled until direct install hardening is complete', () async {});
test('inventory confirms existing installed source authority before adding repository registry', () async {});
test('source packages are refresh-derived and rebuildable', () async {});
test('can add repository index url and refresh packages', () async {});
test('legacy official array repository schema remains supported', () async {});
test('legacy comicSourceListUrl migrates into repository registry once', () async {});
test('repository registry seeds built-in default repositories when legacy setting missing', () async {});
test('repository registry uses canonical app db and does not create sidecar files', () async {});
test('object repository schema is supported', () async {});
test('invalid repository index url shows typed error', () async {});
test('repository refresh failure does not delete or mutate installed sources', () async {});
test('repository refresh is serialized per repository and does not corrupt package cache', () async {});
test('removing repository does not remove installed source by default', () async {});
test('can install source from repository package', () async {});
test('can install source from direct javascript url after confirmation', () async {});
test('direct javascript source rejects non https url by default', () async {});
test('direct javascript source rejects html response masquerading as script', () async {});
test('direct javascript source enforces script size limit', () async {});
test('direct javascript validation runs outside ui isolate with timeout', () async {});
test('direct javascript source records install origin where supported', () async {});
test('direct javascript source records content hash where supported', () async {});
test('direct javascript update blocks source key mismatch', () async {});
test('concurrent update and remove for same source returns typed conflict', () async {});
test('source key collision requires explicit confirmation', () async {});
test('local source file import uses same source management controller', () async {});
test('home source shortcut and settings source page use same controller', () async {});
test('installed source reorder remains available from settings', () async {});
test('installed source delete remains available from settings', () async {});
test('source management command error shows visible typed error state', () async {});
test('repository command failure renders visible typed error', () async {});
test('repository row displays last refresh failure code', () async {});
test('source diagnostics redact auth headers device identifiers and signatures', () async {});
test('source diagnostics redact signed query parameters', () async {});
test('source diagnostics do not persist raw source script content by default', () async {});
```

## Verification Commands

```bash
flutter test test/features/source_management
flutter test test/pages/settings_comic_sources_test.dart
flutter test test/pages/source_repository_registry_test.dart
flutter test test/pages/source_direct_js_install_test.dart
flutter test test/features/source_management/source_repository_schema_test.dart
flutter test test/features/source_management/source_management_redaction_test.dart
dart analyze lib/features/source_management lib/pages/settings lib/pages test/features/source_management test/pages
git diff --check
```

## Exit Criteria

- `Settings > Comic Sources` is the canonical source management surface.
- Users can add repository `index.json` URLs from Settings.
- Users can install direct JavaScript source URLs from Settings.
- Users can import local source files from Settings.
- Installed and available sources are visually separated.
- Repository management, Add / Import, Available Sources, and Installed Sources are presented in a single Settings source surface.
- Legacy source-list popup entrypoint is not exposed from the Settings source management surface.
- Available source install remains disabled until Direct JS install hardening is complete.
- Multiple repositories are supported.
- Legacy `comicSourceListUrl` seeds the repository registry once and stops being active authority.
- Missing legacy `comicSourceListUrl` seeds both built-in default repositories.
- Repository registry metadata is stored in the canonical app DB only.
- Legacy official array index shape remains supported.
- Object repository schema is supported.
- Repository package metadata is rebuildable and non-authoritative.
- M26.2 does not create duplicate installed source authority.
- Repository refresh failure does not delete or mutate installed sources.
- Repository refresh is serialized per repository.
- Install/update/remove commands for the same source are serialized or return typed conflict.
- Repository removal does not remove installed sources by default.
- Existing installed source order/settings remain preserved.
- Home/Search source page is only a shortcut, not the only add-source path.
- Add/update/remove/reorder actions use one shared controller.
- Source management command errors render visible typed UI state.
- Repository command failures render user-safe typed errors rather than raw exception strings.
- Repository rows expose typed refresh status/error codes when refresh fails.
- Source management diagnostics redact auth headers, cookies, device identifiers, signatures, and signed query parameters.
- Source script contents are not persisted in diagnostics by default.
- Direct JS validation is isolated from the UI isolate and has timeout handling.
- Sensitive diagnostics are redacted.
- No ReaderNext, appdata, cache, cookie, or deep source runtime semantics are changed.
