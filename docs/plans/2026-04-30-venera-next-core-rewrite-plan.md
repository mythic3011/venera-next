# Venera Next Core Rewrite Plan

## Decision Lock

This fork is now in **core rewrite mode**.

Do not frame current work as conservative refactor of the old
local/history/favorite/source core.

The active execution model is:

- Strangler-style core rewrite
- old core is being replaced, not repaired
- old core may only be touched for:
  1. unblocking extraction
  2. preserving buildability

Everything else must move toward the new canonical core.

Current implementation note (2026-04-30):

- remote detail and reader flows now canonicalize remote provenance into
  canonical comic/chapter/page records
- remote reader dispatch prefers canonical remote page state first, with
  deterministic fallback to live source page loading when canonical remote
  state is absent

## Rewrite Model

Keep:

- Flutter app shell
- navigation and route shell
- reusable UI components
- isolated source plugin execution layer where it does not own domain truth
- image rendering widgets that do not own domain state
- build, release, and platform glue

Rewrite:

- canonical domain database
- comic identity model
- source/platform resolver
- shared local/remote search and discovery model
- shared source-provider/data-source model
- provenance-link model instead of overloaded source-object naming
- local import pipeline
- source provenance and citation
- chapters, pages, and page-order overlays
- favorites, history, sessions, and tabs
- reader load planner
- structured diagnostics and export

## Breaking-Change Contract

This is a breaking fork.

Hard rules:

1. `data/venera.db` is the only canonical domain database.
2. `local.db`, `history.db`, `local_favorite.db`, and hidden JSON domain state
   are not runtime contracts.
3. No new runtime fallback reads from legacy DBs or hidden JSON state.
4. No dual-write compatibility layer.
5. Legacy import, if implemented, is explicit and best-effort only.
6. New writes target the new canonical model only.
7. Migration/import failure must fail loudly and be observable.

## Architectural Rationale: Local / Remote Was The Wrong Primary Boundary

The legacy design incorrectly treated local and remote comics as separate
primary domain objects.

That boundary is wrong.

Local and remote are data-source states around one canonical comic identity,
not two different comic products.

```text
Wrong:
  LocalComic
  RemoteComic

Correct:
  Comic
  DataSource
  ComicSourceLink / ProvenanceLink
  UserOverlay
  ReaderState
```

The damage caused by the old split:

- duplicated UI paths
- duplicated search and detail behavior
- duplicated favorite and history mapping
- import, download, and match flows cannot merge cleanly
- reader, debug, and smoke verification must reconstruct truth across multiple stores
- local comic becomes a thin file item
- remote comic becomes the only "real" comic entity

New model:

```text
Comic
  = canonical identity
DataSource
  = local / remote / aggregate / import / manual metadata provider
DataSourceCandidate
  = possible result returned by a data source
ProvenanceLink
  = confirmed relationship between Comic and DataSource
UserOverlay
  = user tags / notes / custom title / favorite / custom page order
ReaderState
  = tabs / sessions / resume state
```

Hard rule:

- local / remote is a source dimension
- not an object type dimension

A local import and a remote provider can both describe the same `Comic`.

They must not produce two separate comic worlds.

## Unified Layer Rule

The new core must not be layered by `local`, `remote`, or source-specific UI
paths.

That was the legacy boundary mistake.

The correct layering is:

```text
UI layer
  - shared search
  - shared detail
  - shared manager
  - shared reader entry
Application layer
  - comic detail service
  - search/discovery service
  - import/match/link service
  - reader session service
  - export service
Domain layer
  - Comic
  - DataSource
  - DataSourceCandidate
  - ProvenanceLink
  - UserOverlay
  - ReaderState
Persistence / integration layer
  - venera.db
  - provider adapters
  - local filesystem/blob storage
  - external source runtimes
```

Hard rules:

- UI does not know two worlds called local and remote
- application services perform capability/state routing
- domain model does not treat raw source keys as truth
- persistence/integration handles local file, remote provider, aggregate
  provider, and external runtime differences

Wrong layering:

```text
local layer
remote layer
source-specific UI layer
```

Correct layering:

```text
shared comic layer
source/provider integration layer
```

UI should still operate through the same shared comic surfaces:

- `ComicSearchSurface`
- `ComicDetailPage(comicId)`
- `ComicManagerPage(comicId)`
- `ReaderEntry(comicId)`

Service boundary:

- UI calls application services, not raw persistence or provider code
- application services are the only allowed orchestration layer

Representative service interfaces:

- `ComicDetailService.getComicDetail(comicId)`
- `SearchDiscoveryService.search(query, scope)`
- `ImportMatchLinkService.importArchive(...)`
- `ImportMatchLinkService.linkCandidate(...)`
- `ReaderSessionService.openComic(...)`
- `ExportService.exportComic(...)`

Repository/persistence boundary:

- persistence must be hidden behind repositories or adapters
- domain code must not know whether data came from SQLite, local filesystem,
  provider runtime, archive importer, PDF parser, or legacy importer
- old stores remain optional legacy import inputs, not runtime truth:
  - `local.db`
  - `history.db`
  - `local_favorite.db`
  - `implicitData.json`

## Layer Ownership And Logging Rule

Every layer must have structured logging and diagnostics, but each layer only
logs the events it owns.

Logging is not a replacement for clean boundaries.

If a UI file needs to log domain decisions, that is usually a boundary smell.

### Layer ownership

```text
UI layer
  Owns:
    - rendering state
    - user intent dispatch
    - visible interaction events
    - route/screen lifecycle
  Must not own:
    - source resolution
    - import rules
    - DB writes
    - provenance decisions
    - page order validation
    - reader lifecycle business rules

Application layer
  Owns:
    - use-case orchestration
    - capability routing
    - import/match/link workflow
    - reader open/resume workflow
    - export workflow
  Must not own:
    - widget rendering
    - raw SQL details
    - provider-specific parsing internals

Domain layer
  Owns:
    - Comic identity
    - DataSource identity
    - Candidate vs Provenance rules
    - UserOverlay rules
    - ReaderState rules
  Must not own:
    - Flutter widgets
    - database implementation
    - filesystem traversal
    - HTTP/plugin runtime details

Persistence / integration layer
  Owns:
    - SQLite repositories
    - local filesystem/blob storage
    - provider adapters
    - archive/PDF/image parsing
    - external source runtime adapters
  Must not own:
    - UI behavior
    - domain policy decisions
    - user-facing workflow decisions
```

### Logging by layer

UI logs:

- `screen_opened`
- `action_clicked`
- `dialog_confirmed`
- `dialog_cancelled`
- `route_changed`
- `unsaved_changes_warning_shown`

Application logs:

- `import_requested`
- `import_plan_created`
- `candidate_link_requested`
- `provenance_link_created`
- `reader_open_requested`
- `reader_load_plan_created`
- `export_requested`
- `export_completed`
- `workflow_failed`

Domain logs or domain events:

- `comic_created`
- `data_source_resolved`
- `candidate_created`
- `candidate_promoted_to_provenance`
- `user_tag_added`
- `page_order_changed`
- `reader_state_changed`

Persistence/integration logs:

- `db_opened`
- `migration_started`
- `migration_completed`
- `query_failed`
- `archive_scanned`
- `archive_entry_skipped`
- `pdf_pages_extracted`
- `provider_request_started`
- `provider_request_failed`
- `blob_written`

### Structured logging requirements

Logs must be structured, not random text dumps.

Each event should include as applicable:

- `timestamp`
- `eventName`
- `layer`
- `severity`
- `correlationId`
- `operationId`
- `comicId`
- `readerSessionId`
- `readerTabId`
- `dataSourceId`
- `provenanceLinkId`
- `pageOrderId`
- `chapterId`
- `pageId`
- `errorType`
- `errorMessage`

### Correlation rule

A single user operation must carry one `correlationId` across layers.

Example chain:

```text
UI: user clicks Import ZIP
-> Application: import_requested
-> Integration: archive_scanned
-> Domain: comic_created
-> Persistence: rows_written
-> Application: import_completed
-> UI: import_result_displayed
```

All events in this chain must share the same `correlationId`.

### File ownership rule

A file must not mix unrelated layer responsibilities.

Bad:

```text
ComicDetailPage.dart
  - renders widgets
  - queries SQLite
  - resolves local/remote source
  - mutates favorites
  - parses archive metadata
  - writes debug export
```

Good:

```text
ComicDetailPage.dart
  - renders ComicDetailViewModel
  - dispatches user intent
ComicDetailService.dart
  - builds detail view model
  - coordinates repositories
ComicRepository.dart
  - loads comics from venera.db
ImportService.dart
  - creates import plan and applies import
ReaderSessionService.dart
  - opens/resumes reader sessions
DiagnosticsService.dart
  - writes structured snapshots and exports
```

Hard rule:

- UI files are not allowed to contain domain, persistence, provider, import,
  export, or lifecycle business logic
- domain files are not allowed to import Flutter UI packages
- persistence/integration files are not allowed to decide user-facing workflow
  policy

If a file renders UI, queries DB, decides local/remote, writes logs, and
mutates reader state at the same time, that file is already a bug factory.

## Package Direction

This core rewrite should use well-scoped packages to reduce development time,
but packages must not own the domain model.

Packages are allowed for:

- infrastructure
- persistence
- routing
- dependency injection and state wiring
- logging and diagnostics
- archive or PDF parsing
- file picking
- code generation

Packages are not allowed to replace the domain boundary.

Hard rule:

- packages may reduce plumbing
- packages must not define domain policy

### Package adoption rule

Before adding a package, answer:

1. which layer owns this package
2. does it reduce plumbing or change domain policy
3. can it be isolated behind an adapter or service
4. does it work on required target platforms
5. does it introduce generated code or `build_runner` cost
6. what is the removal path if the package becomes a problem

Good:

- Drift owns SQLite access
- archive owns ZIP parsing
- PDF package owns page rendering
- Riverpod wires services
- Freezed generates immutable models

Bad:

- UI provider decides local vs remote identity
- archive parser creates `Comic` directly without `ImportService`
- PDF parser writes DB rows directly
- logger becomes the only source of debug truth
- reorder UI mutates `pages.page_index`

## Recommended Package Set

Package direction should support the rewrite while keeping domain ownership in
repo code.

### Canonical DB and persistence

Use Drift for the canonical relational database direction.

Target ownership:

- persistence layer only
- SQLite access, joins, transactions, migrations, DAOs, and reactive queries

Planned package set:

```yaml
dependencies:
  drift: any
  drift_flutter: any
dev_dependencies:
  drift_dev: any
  build_runner: any
```

### State and application wiring

Use Riverpod for state injection and application-service access.

Use it for:

- service providers
- repository providers
- view-model state
- reader-state observation

Do not put domain rules directly inside UI providers.

Planned package set:

```yaml
dependencies:
  flutter_riverpod: any
```

### Immutable domain and view models

Use Freezed and JSON codegen for immutable domain/view models.

Candidate model families:

- `Comic`
- `DataSource`
- `DataSourceCandidate`
- `ProvenanceLink`
- `UserOverlay`
- `ReaderState`
- `ReaderDebugSnapshot`
- `ImportPlan`
- `ImportResult`

Planned package set:

```yaml
dependencies:
  freezed_annotation: any
  json_annotation: any
dev_dependencies:
  freezed: any
  json_serializable: any
  build_runner: any
```

### Routing

Use explicit shared route structure for unified comic surfaces.

Preferred route direction:

- `/comics/:comicId`
- `/comics/:comicId/manage`
- `/comics/:comicId/reorder`
- `/reader/:readerTabId`
- `/import`

Planned package set:

```yaml
dependencies:
  go_router: any
```

### Dependency injection

Prefer Riverpod first.

Only consider `get_it` if low-level singleton infrastructure becomes noisy and
Riverpod alone is no longer sufficient.

### Archive import

Use archive parsing packages only in the integration layer.

Use cases:

- scanning archive entries
- detecting nested archives
- extracting image entries
- skipping unsupported files
- recording skipped entries

Planned package set:

```yaml
dependencies:
  archive: any
```

### File picking and filesystem

Use filesystem/picker packages only in the integration layer.

The domain and application layers should receive normalized paths or import
requests, not call file pickers directly.

Planned package set:

```yaml
dependencies:
  file_picker: any
  path: any
  path_provider: any
```

### PDF handling

Use PDF rendering/parsing only in the integration layer.

Acceptance before adoption:

- can render or extract page thumbnails
- works on required desktop/mobile targets
- does not force UI dependencies into the domain layer
- fails gracefully on encrypted or corrupt PDF

Evaluation candidates may be added later after this acceptance gate is checked.

### Reorder UI helper

Use drag/reorder grid/list packages only for UI convenience.

Hard rule:

- the package may help interaction
- saved truth remains `page_order_items.sort_order`

### Logging and diagnostics

Use structured logging packages as infrastructure only.

Minimum direction:

```yaml
dependencies:
  logging: any
```

Optional debug/export helpers may be evaluated later, but they must not become
the domain boundary or the only source of debug truth.

### HTTP and remote provider adapters

If current networking becomes a bottleneck, evaluate a dedicated HTTP package in
the provider adapter layer only.

Hard rule:

- remote provider adapters must not leak into UI files

## Minimal Package Adoption Order

Start with the smallest useful package set for V0 and V1:

```yaml
dependencies:
  drift: any
  drift_flutter: any
  flutter_riverpod: any
  freezed_annotation: any
  json_annotation: any
  go_router: any
  archive: any
  file_picker: any
  path: any
  path_provider: any
  logging: any
dev_dependencies:
  build_runner: any
  drift_dev: any
  freezed: any
  json_serializable: any
```

Later evaluation bucket:

- PDF page rendering package
- optional debug UI/export helper
- optional dedicated HTTP client
- optional reorder-grid helper

Rule:

- buy core tools first
- do not front-load a dependency pile that recreates the same architecture
  mess in package form

## Old/New Boundary Contract

### New core owns

- `lib/foundation/db/**` canonical DB and schema authority
- `lib/foundation/source_identity/**` source/platform identity authority
- `lib/foundation/comic_detail/**` unified comic read model
- new import, provenance, page-order, session, and debug repositories
- `ComicDetailPage(comicId)` as the unified detail entry point

### Old core may remain temporarily for

- app-shell routing continuity
- buildability while extraction is in progress
- compatibility UI surfaces that have not yet been switched to new-core reads
- source runtime execution that has not yet been rebound to canonical state

### Old core must not regain authority over

- comic identity
- favorites truth
- history truth
- local library truth
- source mapping truth
- session/tab truth
- reader page-order truth

## Kill-Switch List For Old Core

Stop repairing these as feature targets:

- `local.db` flow
- `history.db` flow
- `local_favorite.db` flow
- widget-owned reader loading
- old logger/exporter path as the main debug surface
- platform-specific `if/else` domain patches
- duplicated favorite/history source mappings
- hidden JSON domain state

Allowed old-core changes:

- extraction shims
- compile fixes
- route handoff glue
- temporary adapters needed to switch call sites to the new core

## Extraction Order

Extract and replace in this order:

1. Canonical DB foundation and open config
2. Source platform authority and compatibility resolver
3. Unified comic identity read model
4. Local import structure
5. Source citation and source tags
6. User tags and library actions
7. Page-order overlay
8. Reader sessions and tabs
9. Unified detail page
10. Remote match flow
11. Structured reader debug snapshot and export

Rules:

- do not start detail-page rewrite before repository/view-model contracts exist
- do not start page-reorder UI before overlay persistence and validation exist
- do not route new feature work back into legacy DBs

## Current Grounded Status

Already implemented in the first rewrite slice:

- canonical DB open path with:
  - `PRAGMA foreign_keys = ON`
  - `PRAGMA journal_mode = WAL`
- `UnifiedComicsStore`
- `SourcePlatformResolver`
- centralized source-identity compatibility handling
- canonical `favorites` support in the new store
- read-only `ComicDetailRepository`
- immutable `ComicDetailViewModel` snapshots
- `LegacyLocalMigrationService` for explicit legacy-local import into canonical
  comic, library-item, chapter, page, and default page-order tables

Current canonical tables already present:

- `source_platforms`
- `source_platform_aliases`
- `comics`
- `comic_titles`
- `local_library_items`
- `chapters`
- `pages`
- `page_orders`
- `page_order_items`
- `history_events`
- `favorites`

This means the rewrite plan must continue from a real foundation, not from
greenfield assumptions.

## V0 Evidence Already Present

The repo already contains working evidence that the fork is in rewrite mode,
not just planning mode.

Existing user-visible vertical-slice evidence includes:

- local comic detail surface
- chapters visible in detail/local flows
- local source badge and basic detail actions
- chapter-management UI
- chapter edit/delete affordances
- drag-reorder affordance
- management tabs for chapters, reorder pages, set cover, and merge

Interpretation rule:

- this evidence proves the fork already has new-core product pressure
- do not treat these surfaces as a reason to keep repairing old
  `local.db`/`history.db`/`local_favorite.db` authority
- instead, use them as cutover targets for canonical data authority

## V0 Done vs Missing

### V0 already done

- local comic has a detail surface
- imported archive/folder content can surface chapters
- chapters can be listed in management UI
- chapter-management UI exists
- chapter reorder affordance exists
- edit/delete/drag affordances exist

### V0 still missing

- canonical `venera.db` write-through/read-through authority for the active UI
- stable chapter, page, and page-order schema as the runtime source of truth
- `ReaderDebugSnapshot`
- import diagnostics export
- structured reader lifecycle/logger events
- removal of user-facing raw legacy IDs
- promotion of current debug/admin local UI into a usable library-manager UX

The practical consequence is:

- V0 is no longer blocked on more legacy-UI invention
- V0 is blocked on canonical data-authority cutover

## User-Facing Identity Rule

Internal IDs are debug/diagnostic identifiers, not product labels.

Rules:

- raw chapter/page/local IDs such as `1`, `2`, `3`, `legacy_local:*`, or other
  storage-shaped identifiers must not be used as user-facing primary labels
- user-facing chapter rows should prefer:
  - chapter order
  - chapter title
  - page count
  - source kind such as PDF, ZIP, or Folder
  - state such as normal, missing pages, or unreadable
- internal IDs remain available to diagnostics, debug snapshots, logs, and
  export bundles

## UX Boundary For V0 And After

Current comic-management UI should be treated as a functional skeleton, not the
finished shared manager experience.

Rules:

- `ComicDetailPage` is the shared read/resume/metadata overview surface for
  both local and remote comics
- `ManageComicPage` is the structure-editing surface for chapters, pages,
  cover, merge, and export workflows across both local and remote comics where
  capabilities permit
- overflow/context menus are for low-frequency contextual actions only
- destructive actions must not sit in the same primary cluster as reorder,
  cover, or export actions

Shared-surface rule:

- local and remote comics must converge on the same detail and manager UX
- differences should come from capability/state gating, not from separate
  product surfaces
- search and discovery must also converge on a shared local/remote surface
- differences should come from scope, source, and capability filters rather
  than separate search products
- multi-source handling must converge on the same shared comic UI rather than a
  separate `Comic Source` product surface

## Source Terminology Contract

`Comic Source` is an overloaded term and must be split clearly in the new core.

### Source provider / data source

This is the system/source integration layer, for example:

- site-specific comic providers
- generic search providers
- metadata lookup providers
- import/match providers

These are product-level data sources and discovery backends.

Important clarification:

- the same comic website may act as a discovery/search data source, a
  content/detail provider, and a comic-level provenance source
- these roles may come from the same website, but they must remain distinct in
  the domain model

### Comic provenance source

This is a comic-level linked source record attached to a canonical comic, for
example:

- downloaded from E-Hentai
- manually matched to PicACG
- imported with metadata from another provider

These belong to the comic identity/provenance model.

Hard rule:

- do not collapse provider-level data sources and comic-level provenance into
  one ambiguous UI concept
- shared UX may expose both, but the model and terminology must stay explicit

Naming direction:

- avoid continuing to use `comic_sources` as the main conceptual name in new
  architecture docs
- prefer `comic_source_links` or `provenance_links` for confirmed comic-to-data
  source relationships
- this keeps `source` from ambiguously meaning provider, candidate, linked
  provenance, or UI surface

## Data Source / Identity / Provenance / Overlay Rule

Local and remote are both data sources.

A comic is not local or remote by type.
A comic is the canonical identity that can be linked to one or more data
sources.

User-added data is not source truth.
User-added tags, notes, custom title, favorite state, and custom page order are
user overlays on top of the canonical comic identity.

```text
DataSource
  = where data can come from
Comic
  = canonical identity
DataSourceCandidate
  = possible match returned by a data source
ComicSourceLink / ProvenanceLink
  = confirmed relationship between a comic and a data source
UserOverlay
  = user-owned metadata and reading preferences
```

Examples:

- local import = `DataSource`
- remote comic website = `DataSource`
- aggregate search over multiple providers = `DataSource` capability
- imported ZIP/PDF metadata = `DataSource` output
- user tag = `UserOverlay`
- remote tag = source metadata
- manual match to remote URL = `ProvenanceLink`
- downloaded from remote provider = `ProvenanceLink`
- search result = `DataSourceCandidate`, not provenance

Hard rules:

- a data source may produce candidates
- a candidate is not provenance
- only explicit import, download, manual match, or accepted promotion creates
  provenance
- widgets, reader flows, and ad hoc UI code must not infer domain truth from
  raw source keys

## Source Role Model

The new core should treat source behavior as a three-layer model.

### 1. Source provider / data source

- owns discovery/search/browse capability
- may also own metadata lookup, match, detail loading, or page loading
- can represent one website/provider or an aggregate provider over multiple
  websites/providers

### 2. Search/discovery surface

- shared user-facing search UI
- can target one provider or multiple providers
- can present aggregated discovery results

### 3. Comic provenance source

- comic-level linked relationship to a provider/source record
- records where the comic came from, was downloaded from, or was matched to

Hard rule:

- provider capability and comic provenance may point at the same website, but
  they are not the same domain role

## Canonical Naming Direction

Planning and schema direction should move toward:

```text
data_sources
data_source_aliases
data_source_capabilities
comics
comic_titles
data_source_candidates
comic_source_links        # or provenance_links
comic_source_link_tags    # remote/source tags attached through link
user_tags
comic_user_tags
user_notes
user_favorites
page_orders
```

Preference:

- `provenance_links` is the least ambiguous name for confirmed comic-to-source
  relationships
- `comic_source_links` is acceptable when a more explicit transition name is
  needed
- avoid using bare `comic_sources` in new architecture language because it
  overloads provider/source/provenance semantics

## Search And Discovery UX Requirements

Search is a shared product surface for both local and remote comics.

Rules:

- do not keep separate local-search and remote-search products as long-term UX
- use one shared search/discovery surface with scope/filter controls
- search results should be able to represent:
  - local only
  - remote only
  - local with linked remote source
  - downloaded
  - unmatched
- search filters may include source/platform, local availability, linked state,
  favorite, tags, and recently read
- result actions should be capability-gated by state, not split by product type
- provider selection may include multiple data sources such as comic providers,
  generic search providers, and future metadata/search integrations
- provider choice belongs to the shared search surface, not a separate product
  silo
- the shared surface should support:
  - single-source mode
  - multi-source aggregate mode

Result-model rule:

- search results should converge on shared comic identity where available
- local/remote duplication should be resolved by canonical comic identity and
  source/provenance state, not by showing separate product worlds
- aggregate search is a provider capability, not a separate product family

Primary visible actions should converge toward:

- Start or Continue
- Favorite
- Manage
- Share

Management actions should be grouped under a dedicated manage surface:

- Manage chapters
- Reorder pages
- Set cover
- Merge
- Export

File/source actions should stay secondary:

- Open folder
- Copy title
- Copy ID

Danger actions must be isolated:

- Delete
- Block

## Detail Surface UX Requirements

The detail page must not remain visually sparse once canonical metadata is
available.

Required detail additions for both local and remote detail states:

- status chips such as local/imported/chapter-count/page-count/source-state
- metadata rows for source, location, last read, import time, and file size
- explicit source state:
  - `Remote source: Not linked` with search action, or
  - linked source state with source URL and verify/view actions
- multi-source state:
  - if a comic has one or more linked sources, show them inside the shared
    detail/source panel
  - if a comic has no linked source, show an add/search source entry surface in
    the same shared detail flow

Chapters on detail must not remain chip-only for larger comics.

Target chapter section:

- searchable/scannable chapter list
- page-count secondary metadata
- source-kind secondary metadata such as PDF, ZIP, or Folder
- optional large-screen multi-pane layout later

## Source Panel UX Requirements

Comic source handling is part of shared comic identity/provenance UX, but it is
not identical to provider selection.

Rules:

- do not keep `Comic Source` as a separate isolated product flow for the same
  comic-level source management problem
- use a shared source panel/section inside the unified comic detail or manager
  flow
- a comic may have multiple linked sources, and the UI should represent that
  explicitly rather than assuming one source only
- provider/data-source selection for search/import/match should stay in the
  shared discovery/search surface, not be confused with per-comic linked source
  management

Required states:

- no source linked:
  - show `Not linked`
  - show add/search source actions
  - show candidate/addable source list when available
- one source linked:
  - show linked source metadata and actions
- multiple sources linked:
  - show source list with primary/secondary distinction
  - allow inspect/view/reverify/set-primary/unlink where capabilities permit

List row content should prefer:

- source display name
- relation type such as downloaded/manual match/auto match
- linked status
- verify state or last-checked state
- source URL or source comic identifier as secondary metadata

Capability rule:

- if no comic source exists, the same shared panel should surface source search
  or source list addition
- if multiple comic sources exist, the same shared panel should surface source
  management rather than sending the user to a different UI world

Provider rule:

- if the user wants to add or use another data source or search provider, that
  belongs to the shared source-provider/discovery model
- adding a provider is not the same action as linking a provenance source to a
  comic

## Manage Surface UX Requirements

The manage surface must behave like a shared comic editor, not a raw DB list.

Default chapter rows should show:

- drag handle
- chapter title
- page count
- source kind
- status
- row more menu

Do not show raw internal IDs as the default visible chapter label.

IDs may be exposed only through:

- debug surface
- copy-ID action
- diagnostics/export

Capability rule:

- remote comics should use the same manager surface where actions make sense
- actions that require local assets or local structure editing may be hidden or
  disabled for remote-only state
- the UX contract is shared even when the allowed action set differs

## Page Reorder UX Requirements

Page reorder is a visual editing workflow, not a filename-sorting workflow.

Hard rules:

- default mode is thumbnail-first
- dense list mode is secondary only
- drag reorder must show insertion feedback
- each page shows current visible order number
- original/source page index may be shown as secondary metadata
- save/reset controls must show dirty-state summary
- `Reset to source order` must be explicit and easy to find

Persistence rules:

- `pages.page_index` remains original import/source order
- custom order writes only to `page_order_items.sort_order`
- reader uses active `page_order_id`

Performance rules:

- use small thumbnail cache rather than full decode
- lazy load visible thumbnails
- thumbnail cache key should be stable to page content and requested size

## Export UX Requirements

Export is a workflow, not an overflow-menu dumping ground.

Use a dedicated export dialog or export manage subflow with:

- format selection: CBZ, PDF, EPUB
- scope selection: all chapters or selected chapters
- order selection: current page order or source order
- options such as include metadata, include cover, include source citation file

## UX Ticket Queue

### UX-001 Unified comic detail layout

- add status chips
- add metadata panel
- add remote source state
- replace chapter chips with chapter list or section

### UX-002 Manage chapters editor

- remove raw ID from default UI
- show page count, source kind, and status
- add row more menu
- keep ID only in debug/copy action

### UX-003 Page reorder editor

- thumbnail grid by default
- optional dense list mode with thumbnail
- drag reorder with insertion feedback
- chapter selector
- save/reset dirty-state summary
- preserve `pages.page_index`

### UX-004 Action grouping

- primary actions visible
- management actions grouped under Manage
- export moved into dialog/subflow
- danger actions isolated

### UX-005 Export dialog

- CBZ/PDF/EPUB format selection
- scope selection
- order selection
- include metadata and source citation options

## Vertical Slices

### V0: Local Import -> Canonical Detail -> Reader Open

Deliver:

- local zip/folder import into `data/venera.db`
- `comics`
- `local_library_items`
- `chapters`
- `pages`
- `page_orders`
- unified `ComicDetailPage(comicId)` read path for local comics
- reader open path for imported local comics from new core
- `ReaderDebugSnapshot` with canonical identifiers

Acceptance:

- user-imported local comic opens by `comicId`
- imported local comic has generated chapters/pages in `venera.db`
- imported local comic detail comes from new repository/model
- reader opens local comic from new-core state
- debug snapshot shows:
  - `comicId`
  - `localLibraryItemId`
  - `pageOrderId`
  - `loadMode`
  - controller lifecycle state

### V1: Provenance, Tags, and Library Management

Deliver:

- `comic_sources`
- `chapter_sources`
- `page_sources`
- `source_tags`
- `comic_source_tags`
- `tags`
- `comic_tags`
- local library sort/filter upgrade
- source citation surface on unified detail page

Acceptance:

- downloaded local comic shows original source name and comic URL
- imported local comic without source shows `Remote source: Not linked`
- local and remote comics both support user tags
- source tags are shown separately and remain read-only by default
- local library sort/filter uses canonical data, not legacy split truth

### V2: Sessions, Remote Match, and Full Unified Detail Swap

Deliver:

- `reader_sessions`
- `reader_tabs`
- `remote_match_candidates`
- related-remote search and explicit candidate promotion
- capability-gated unified detail actions
- remove active local-vs-remote detail split as product surface

Acceptance:

- local comic and remote comic open through the same detail page
- local comic opens in a new tab through canonical session state
- pending remote candidate is not source citation
- accepted candidate can promote into `comic_sources`
- page-order selection and session restore come from canonical state

## Multi-Agent Lane Split

Use parallel implementation with serial integration.

### Lane A: Canonical Storage and Compatibility

Own:

- `lib/foundation/db/**`
- `lib/foundation/source_identity/**`
- schema evolution
- import/migration helpers
- canonical favorite/history consolidation

Must not own:

- detail page widgets
- reader presentation widgets
- platform identity metadata

### Lane B: Unified Comic Domain

Own:

- `lib/foundation/comic_detail/**`
- local import repository/service work
- provenance and tag repositories
- remote match domain rules

Must not own:

- legacy DB readers as feature targets
- reader presentation/controller code
- platform identity metadata

### Lane C: Reader Runtime and Diagnostics

Own:

- reader sessions/tabs persistence
- canonical reader load planning
- page-order consumption in reader
- `ReaderDebugSnapshot`

Must not own:

- storage fallback bridges
- detail-page UI composition
- source/platform resolver semantics

### Lane D: Unified Detail and Library UI

Own:

- `ComicDetailPage(comicId)` UI swap
- local library manager integration
- capability-gated actions
- sort/filter UX

Must not own:

- DB schema/migration code
- resolver internals
- legacy persistence compatibility

## Integration Queue

All lane work merges through a serial queue:

1. refresh from current accepted base
2. run lane-local tests
3. run `flutter analyze`
4. inspect diff for ownership leaks
5. merge one lane at a time
6. rerun affected cross-lane tests

Do not allow parallel direct pushes to the same integration tip.

## Test And Debug Acceptance Criteria

### V0

- focused DB tests for canonical tables and DB open config
- source resolver compatibility tests
- comic detail repository tests for local-only state
- import structure tests for flat-folder and nested-folder chapter generation
- reader open smoke using canonical page-order data
- debug snapshot shows active canonical IDs and load state

### V1

- provenance query tests
- source-tag vs user-tag separation tests
- downloaded/imported source-state tests
- local library sort/filter repository tests

### V2

- session/tab persistence tests
- remote candidate promotion tests
- page-order consumption tests
- unified detail capability-gating tests
- debug snapshot proves:
  - `comicId`
  - `localLibraryItemId`
  - `comicSourceId`
  - `readerTabId`
  - `pageOrderId`
  - `loadMode`
  - source citation state
  - page-order state

## Immediate Next Slice

The next slice should stay inside V0 completion:

1. local import writer into canonical tables
2. source-default page-order creation during import
3. unified local comic detail route by `comicId`
4. reader open path bound to canonical local comic state
5. first `ReaderDebugSnapshot`

Do not widen back into legacy storage repair while V0 is incomplete.
