# Unified Comic Detail + Local/Remote Library Implementation Plan

## Status

- This is a supporting implementation backlog for the unified comic
  architecture.
- The canonical execution and boundary document is
  `docs/plans/2026-04-30-venera-next-core-rewrite-plan.md`.
- This plan assumes the fork is allowed to make a deliberate breaking change.
- Legacy fragmented storage is not a runtime compatibility target.

Implemented truth snapshot (2026-04-30):

- remote comic provenance is canonicalized at detail sync
- remote chapter/page provenance is canonicalized during reader page sync
- remote reader page loading now prefers canonical remote page state and
  falls back to live source loading when canonical remote state is missing

Related source-of-truth docs:

- `docs/plans/2026-04-30-unified-comic-detail-local-remote-architecture.md`
- `docs/plans/2026-04-30-venera-next-core-rewrite-plan.md`
- `docs/plans/lane-c-phase1-minimal-runtime-core.md`

## Breaking-Change Contract

This plan is based on an explicit breaking-change decision and must be read as
rewrite execution support, not old-core preservation work.

Hard rules:

1. `data/venera.db` becomes the sole domain authority.
2. `local.db`, `history.db`, `local_favorite.db`, and hidden JSON domain state
   are legacy import inputs only.
3. No new runtime fallback reads from legacy DBs.
4. No dual-write to old DBs.
5. Legacy import, if implemented, is explicit and observable.
6. Failure during migration/import must fail loudly.

This means the implementation plan must not preserve the old multi-DB runtime
contract by accident while adding the new unified comic model.

Additional rewrite lock:

- old core may only be changed for extraction or buildability
- old local/history/favorite/source flows are not feature repair targets

## Old-Core Kill Rules

Apply these rules to every implementation slice:

1. `data/venera.db` is the only target authority for new domain writes.
2. `local.db`, `history.db`, `local_favorite.db`, and hidden JSON state are
   import inputs only.
3. No dual-write and no runtime fallback reads.
4. Any surviving legacy adapter must declare whether it exists for import,
   diagnostics mapping, or compile compatibility, plus its deletion gate.
5. `LocalManager` and equivalent legacy managers must not remain long-term
   domain authority.
6. New UI work must route toward `ComicDetailPage(comicId)` rather than create
   fresh local-only or remote-only detail authorities.

## Goal

Route both local and remote comics through one domain model and one detail page:

- `ComicDetailPage(comicId)`

Unify:

- comic identity
- local storage state
- source provenance
- user tags
- source tags
- chapters/pages
- page-order overlays
- reader tabs/sessions
- remote match candidates

Do not unify by flattening meaning. Local storage, remote provenance, user
metadata, and source metadata remain separate tables and services.

## Out of Scope

Not part of this plan:

- broad black-screen branch merges
- new state-management framework
- preserving old DBs as runtime authorities
- mutating `pages.page_index` for custom order
- mixing user tags with source tags
- auto-accepting remote source matches

## Dependency Order

Implementation must follow this order:

1. Canonical DB foundation
2. Source platform authority
3. Unified comic identity tables
4. Read-only unified comic detail repository
5. Local import structure
6. Source citation
7. User tags and source tags split
8. Page-order overlay
9. Reader sessions/tabs
10. Unified detail UI
11. Remote match flow
12. Debug snapshot and migration report

Do not start UI unification before read models exist.
Do not start page reorder UI before overlay tables and validation exist.
Do not start local/remote merge UX before source provenance is modeled.

## Phase Plan

### Phase 0: Freeze Legacy Authority Surface

Scope:

- document canonical DB target
- document breaking-change policy
- remove assumptions that old DBs remain runtime truth

Acceptance:

- all active plans point at `venera.db` as the target authority
- no new work introduces legacy fallback as a design requirement

### Phase 1: Canonical DB Foundation

Scope:

- create `data/venera.db` store
- enable `PRAGMA foreign_keys = ON`
- enable `PRAGMA journal_mode = WAL`
- add foundational tables:
  - `source_platforms`
  - `source_platform_aliases`
  - `comics`
  - `comic_titles`
  - `local_library_items`
  - `history_events`
  - `favorites`

Acceptance:

- DB opens with foreign keys and WAL
- resolver-level tests pass
- new writes can target canonical tables without touching old DBs

### Phase 2: Source Platform Resolver

Scope:

- add `SourcePlatformResolver`
- move source key / legacy type / alias resolution into one authority
- remove duplicated favorite/history mappings from caller logic

Acceptance:

- favorite/history do not own separate mapping tables in code
- resolver supports canonical key, legacy key, and legacy int type
- compatibility is read through resolver only

### Phase 3: Unified Comic Identity Read Model

Scope:

- add `ComicDetailRepository`
- add `ComicDetailViewModel`
- add `SourcePlatformRef`
- support `localOnly`, `remoteOnly`, `localWithRemoteSource`, `downloaded`,
  `unavailable`

Acceptance:

- one repository can return a read-only detail VM by `comicId`
- local and remote comics are both addressable through the same VM shape
- UI rewrite is still deferred in this phase

### Phase 4: Local Import Structure

Scope:

- add `import_batches`
- add `chapters`
- add `pages`
- generate source-default page order for imported content

Acceptance:

- flat folder import becomes one chapter
- nested folders become multiple chapters
- imported local comic has readable chapter/page structure in canonical DB

### Phase 5: Source Citation and Source Tags

Scope:

- add `comic_sources`
- add `chapter_sources`
- add `page_sources`
- add `source_tags`
- add `comic_source_tags`

Acceptance:

- downloaded local comic can show original source/platform and source URL
- imported local comic without linked source shows `Not linked`
- pending remote candidates do not appear as source citation

### Phase 6: User Tags and Library Actions

Scope:

- add `tags`
- add `comic_tags`
- add repositories for add/remove/copy flows
- keep source tags read-only by default

Acceptance:

- local comic can add/remove user tags
- remote comic can add/remove user tags
- source tags are displayed separately from user tags

### Phase 7: Page-Order Overlay

Scope:

- add `page_orders`
- add `page_order_items`
- add validation and active-order switching rules

Acceptance:

- reorder is stored as overlay only
- reset-to-source-default works
- hidden-page behavior works without mutating `pages.page_index`

### Phase 8: Reader Sessions and Tabs

Scope:

- add `reader_sessions`
- add `reader_tabs`
- add `ReaderSessionRepository`

Acceptance:

- local comic can open in a new tab
- remote comic can open in a new tab
- tab restore and last-read state come from canonical DB

### Phase 9: Unified Detail UI

Scope:

- replace local-only and remote-only detail divergence with
  `ComicDetailPage(comicId)`
- capability-gate actions from repository output

Acceptance:

- local and remote comics use the same detail page
- actions are state-driven, not object-type-driven
- no duplicate detail logic remains as active surface

### Phase 10: Remote Match Flow

Scope:

- add `remote_match_candidates`
- search candidates by title aliases
- explicit accept/reject/promotion workflow

Acceptance:

- pending candidate is not citation
- accepted candidate can promote into `comic_sources`
- rejected/ignored candidates remain audit/debug state only

### Phase 11: Debug Snapshot and Migration Report

Scope:

- add `ReaderDebugSnapshot`
- add migration report/export surface
- print active DB path and resolved state

Acceptance:

- debug snapshot reports `comicId`, `localLibraryItemId`, `comicSourceId`,
  `readerTabId`, `pageOrderId`, `loadMode`
- source-resolution and page-order state are inspectable without generic log
  scraping

## Lane Split

Recommended execution lanes after Phase 1 foundation lands:

### Lane A: Canonical Storage + Migration

Own:

- DB schema
- import/migration logic
- history/favorite consolidation
- migration report

Do not own:

- detail UI widgets
- reader presentation code

### Lane B: Unified Comic Domain + Detail Read Model

Own:

- repository/view-model layer
- local import modeling
- source citation and tag read model
- remote match promotion rules

Do not own:

- legacy DB readers
- platform identity/distribution metadata

### Lane C: Reader Runtime + Sessions + Debug

Own:

- reader sessions/tabs
- debug snapshot
- page-order consumption in reader

Do not own:

- storage fallback bridges
- detail page UI composition

### Lane D: Unified Detail UI + Local Library Manager

Own:

- `ComicDetailPage(comicId)`
- local library list/detail integration
- capability-gated actions

Do not own:

- resolver semantics
- migration logic

## Multi-Agent Execution Contract

Use parallel diagnosis / implementation with serial integration.

Hard rules:

1. One lane per branch/worktree.
2. One lane owns one bounded write surface.
3. No lane may silently edit another lane's owned files.
4. Merge through an integration queue, not direct parallel pushes to the same
   branch tip.
5. Rebase/refresh lane branches only at approved integration checkpoints.

Execution order:

1. land Lane A foundation slices first
2. land Lane B read-model slices on top of Lane A
3. land Lane C reader/session slices after required storage/read-model
   contracts exist
4. land Lane D UI swap only after B and C contracts are stable

## Lane Ownership Table

### Lane A: Canonical Storage + Migration

Own files/modules:

- `lib/foundation/db/**`
- `lib/foundation/source_identity/**`
- storage migration/import helpers
- DB schema tests

Allowed shared touch points:

- repository constructors/signatures if required for compile

Forbidden files:

- `lib/pages/**`
- reader presentation widgets
- detail page widgets
- platform identity/distribution metadata

Lane deliverables:

1. canonical `venera.db` store foundation
2. source platform tables and resolver
3. history/favorite consolidation plan and imports
4. migration report/export primitives

Required verification:

- focused DB/schema tests
- resolver tests
- migration idempotency tests
- `flutter analyze`

PR boundaries:

- PR A1: DB open config + base tables
- PR A2: source resolver consolidation
- PR A3: legacy local/history/favorite import slices

### Lane B: Unified Comic Domain + Detail Read Model

Own files/modules:

- `lib/foundation/comic_detail/**`
- domain repositories for comics/sources/tags/remote matches
- read-model tests

Allowed shared touch points:

- `lib/foundation/db/**` read APIs only
- model exports needed to compile

Forbidden files:

- `lib/pages/reader/**`
- runtime session/debug controller code
- platform/build metadata
- legacy DB direct readers

Lane deliverables:

1. `ComicDetailRepository`
2. `ComicDetailViewModel`
3. local/remote unified read states
4. source citation read model
5. source tags vs user tags split
6. remote match promotion rules

Required verification:

- repository unit tests
- local/remote state tests
- source citation tests
- `flutter analyze`

PR boundaries:

- PR B1: read-only comic detail repository
- PR B2: local import structure + chapter/page read model
- PR B3: source citation + tags + remote match read model

### Lane C: Reader Runtime + Sessions + Debug

Own files/modules:

- `lib/foundation/comic_source/runtime/**`
- reader session repositories
- reader tab/page-order consumption
- debug snapshot/export

Allowed shared touch points:

- DB read/write surface already exposed by Lane A
- comic detail/session contracts exposed by Lane B

Forbidden files:

- local library list/detail UI widgets
- source resolver semantics
- migration fallback bridges
- platform/build metadata

Lane deliverables:

1. reader sessions/tabs in canonical DB
2. page-order consumption path
3. structured `ReaderDebugSnapshot`
4. smoke/debug export surface

Required verification:

- reader session tests
- page-order consumption tests
- debug snapshot tests
- `flutter analyze`

PR boundaries:

- PR C1: session/tab persistence
- PR C2: page-order reader integration
- PR C3: debug snapshot + smoke diagnostics

### Lane D: Unified Detail UI + Local Library Manager

Own files/modules:

- `lib/pages/**` detail and local library surfaces
- capability-gated action wiring
- local library sort/filter UX

Allowed shared touch points:

- repository/view-model interfaces from Lanes B/C

Forbidden files:

- DB schema/migration code
- resolver internals
- platform/build metadata

Lane deliverables:

1. `ComicDetailPage(comicId)`
2. local library manager/list integration
3. shared local/remote detail UX
4. capability-gated actions

Required verification:

- widget/smoke tests where feasible
- manual local/remote detail sanity pass
- `flutter analyze`

PR boundaries:

- PR D1: read-only unified detail page shell
- PR D2: local library manager integration
- PR D3: action wiring and duplicate-UI removal

## Integration Queue

Every lane merge must pass through this queue:

1. refresh branch from current accepted base
2. run lane-local tests
3. run `flutter analyze`
4. inspect diff for ownership leaks
5. merge one lane PR at a time
6. re-run affected cross-lane tests after merge

Required post-merge checks:

- after A -> re-run B/C compile surfaces
- after B -> re-run D compile surfaces
- after C -> re-run reader/session smoke checks
- before D final merge -> run unified local/remote manual acceptance pass

## Suggested Branch Names

Suggested lane branch/worktree names:

- `lane-a-canonical-storage`
- `lane-b-unified-comic-domain`
- `lane-c-reader-runtime`
- `lane-d-detail-ui`

Suggested integration branches for serial merge:

- `integration/unified-comic-a`
- `integration/unified-comic-b`
- `integration/unified-comic-c`
- `integration/unified-comic-final`

## Merge Gates

Do not merge a lane if any of the following is true:

- it edits files outside its owned scope without explicit approval
- it reintroduces legacy runtime fallback
- it adds UI logic that decides local-vs-remote authority itself
- it mutates `pages.page_index` for custom order
- it mixes source tags with user tags
- it depends on hidden JSON state as domain truth

## Recommended First Parallelizable Cut

The first safe parallel split is:

- Lane A works on canonical DB foundation + resolver
- Lane B prepares read-model interfaces against mocked/fixed contracts only

Do not start Lane C or D in parallel until:

- base DB contracts exist
- resolver authority is stable
- read-only comic detail VM shape is accepted

## Required Stop Points

Stop and verify at these boundaries:

1. after canonical DB foundation
2. after resolver consolidation
3. after read-only unified detail repository
4. after local import structure
5. after source citation
6. after page-order overlay
7. after reader sessions
8. before final UI swap

Do not combine more than one stop point into one unreviewable mega-PR.

## Test Strategy

Required verification layers:

1. unit tests for resolver/source mapping
2. DB tests for FK, unique, and partial-unique behavior
3. repository tests for local/remote/detail states
4. import tests for folder/archive -> chapters/pages
5. reader/session tests for tab restore and page-order consumption
6. smoke/debug tests for snapshot output
7. `flutter analyze`

Required compatibility tests:

- legacy favorite/history source values resolve through unified resolver
- old hash/int compatibility remains readable where still required for import
- migration/import is idempotent
- old DB files are not written after migration

## Acceptance

The plan is complete only when all of the following are true:

- local comic and remote comic open through `ComicDetailPage(comicId)`
- imported local comic has chapters/pages in `venera.db`
- downloaded local comic shows source citation
- local comic can add/remove user tags
- page reorder uses overlay tables only
- reader tabs work for both local and remote comics
- source tags remain separate from user tags
- pending remote candidates are not treated as provenance
- debug snapshot proves canonical source/session/page-order state
- runtime no longer depends on old DBs as active domain truth

## Immediate First Slice

The first executable slice should be:

1. create canonical `data/venera.db` store
2. add DB open config with FK + WAL
3. add `source_platforms` and `source_platform_aliases`
4. add `SourcePlatformResolver`
5. move favorite/history/source-key compatibility into resolver
6. add `comics`, `comic_titles`, `local_library_items`
7. expose read-only `ComicDetailRepository.getComicDetail(comicId)`

This is the narrowest slice that moves the repo toward the unified architecture
without reinforcing the legacy storage split.
