# Unified Comic Detail + Local/Remote Library Architecture

## Status

- Approved target architecture for Venera local/remote comic management.
- This supersedes the older local-only management direction in
  `docs/plans/2026-04-28-local-comic-management-design.md` whenever the two
  conflict.
- The old local manager work remains useful as a UI sub-surface, but it is no
  longer the domain boundary.

## Decision

Do **Unified Comic Detail + Unified Local Library Management**.

Do not treat local comics as thin file items with a separate detail UX.
Do not treat remote comics as a separate UI object.

Use one domain identity:

- `ComicDetailPage(comicId)`

`local`, `remote`, `downloaded`, `imported`, `matched`, and `unavailable` are
state/provenance around the comic. They are not separate detail-page products.

## Problem

Current behavior is split incorrectly:

- Remote comic has full detail UX, source metadata, tags, chapters, reader
  session behavior.
- Local comic is treated like a weak file/folder item with partial metadata and
  weak management.

This is the wrong abstraction. A local comic is still a comic. A remote comic
is still a comic. Storage, provenance, and reader state must be modeled
separately from the unified comic identity.

## Core Rules

Common identity:

- `comics`

Storage and provenance:

- `local_library_items`
- `comic_sources`
- `remote_match_candidates`

Metadata:

- `tags` / `comic_tags` for user-owned tags
- `source_tags` / `comic_source_tags` for source-provided tags
- `comic_titles` for alias/original/import/source titles

Reading structure and overlays:

- `chapters`
- `pages`
- `page_orders`
- `page_order_items`

Reader state:

- `reader_sessions`
- `reader_tabs`

Hard rules:

- Local comics can have full functionality.
- Local metadata must not overwrite source provenance.
- Source metadata can enrich a comic.
- Source metadata must not silently overwrite user-owned local metadata.
- Pending remote matches are not source citation.
- Page reorder is an overlay and must not mutate `pages.page_index`.
- Widgets stay render/composition only.
- Repositories/services own source resolution, local import, page-order
  validation, and session mutation.

## Unified UX

### Local Library

Upgrade local library into a real manager:

- Search
- Filter
- Sort
- Import
- Source/provenance badges
- User tags
- Chapter/page counts
- Last read
- Imported/downloaded date
- Status badges

Target sort/filter surface:

- Title
- Last read
- Imported date
- Updated date
- Source/platform
- Tag
- Chapter count
- Page count
- File size
- Matched/unmatched state
- Favorite
- Has custom page order

### Unified Detail Page

Replace separate local/remote detail assumptions with:

- `ComicDetailPage(comicId)`

Capability-gated tabs/actions:

- Chapters
- Tags
- Source
- Sessions
- Page Order
- Related Remote

Library state examples:

- `localOnly`
- `remoteOnly`
- `localWithRemoteSource`
- `downloaded`
- `unavailable`

## Storage Direction

The current layout is a fragmented filesystem monolith:

- `appdata.json`
- `history.db`
- `local_favorite.db`
- `local.db`
- `cache.db`
- `cookie.db`
- `comic_source/`
- `local/`
- `logs*.txt`
- `implicitData.json`

This is not the target design. It splits domain truth across multiple DBs and
JSON files, which makes local/remote merge, migration, smoke validation,
backup/restore, and transaction safety much harder than they need to be.

The target design is one canonical relational database plus filesystem blobs:

```text
venera/
  data/
    venera.db
    venera.db-wal
    venera.db-shm
  blobs/
    covers/
    pages/
    imports/
    cache/
  plugins/
    comic_source/
  logs/
    app.log
    exports/
  config/
    appdata.json
    window_placement.json
  cookies/
    cookies.db
```

Rules:

- `data/venera.db` is the canonical domain database.
- Filesystem blobs are not domain truth; they are referenced assets.
- `cookies/cookies.db` may remain separate because auth/session lifecycle is
  different from comic domain state.
- cache may remain separate or be represented as blob storage because it is
  wipeable and not domain truth.
- `appdata.json` must contain app preferences only, not hidden domain state.
- `history.db`, `local_favorite.db`, `local.db`, and `implicitData.json` are
  migration inputs, not long-term authorities.

Use SQLite as the local complex-data authority. Existing Venera already uses
`sqlite3` and Drift-backed stores, so the new schema should stay SQLite-first,
but the end state is a single canonical DB, not a family of peer DB files.

Mandatory DB rules:

- Enable `PRAGMA foreign_keys = ON`
- Enable `PRAGMA journal_mode = WAL`
- Use `UNIQUE` and partial unique indexes where ownership rules require it
- Keep source citation, user tags, and page-order overlays in separate tables
- Do not depend on WAL to paper over broken domain boundaries; WAL improves
  concurrency, it does not replace transactional domain design

Foundation tables:

- `source_platforms`
- `source_platform_aliases`
- `comics`
- `comic_titles`
- `comic_sources`
- `local_library_items`
- `import_batches`
- `tags`
- `comic_tags`
- `source_tags`
- `comic_source_tags`
- `chapters`
- `pages`
- `chapter_sources`
- `page_sources`
- `chapter_collections`
- `chapter_collection_items`
- `page_orders`
- `page_order_items`
- `reader_sessions`
- `reader_tabs`
- `remote_match_candidates`

Canonical DB also owns:

- `history_events`
- `favorites`

Canonical DB does not keep:

- separate `history.db` as domain truth
- separate `local_favorite.db` as favorite truth
- separate `local.db` as local comic truth
- JSON files for hidden domain state

## Source Platform Resolver

The current app still carries too many ad hoc source-key mappings. The unified
resolver should become the single authority:

- resolve by canonical key
- resolve by legacy key
- resolve by legacy integer type
- resolve by context (`favorite`, `history`, `reader`, `download`, `import`)

Required outcome:

- favorite/history do not own separate hard-coded source mappings
- source aliases live in one resolver-backed source platform layer

## View Models

Primary detail VM:

- `ComicDetailViewModel`

Required fields:

- `comicId`
- title / cover
- library state
- primary source citation
- user tags
- source tags
- chapters
- reader tabs
- page-order summary
- capability-gated actions

Primary source platform VM:

- `SourcePlatformRef`

Required fields:

- `platformId`
- `canonicalKey`
- `displayName`
- `kind`
- matched alias
- matched alias type
- optional legacy integer type

## Repositories and Services

Required boundaries:

- `ComicDetailRepository`
- `SourcePlatformResolver`
- `LocalImportService`
- `ComicSourceRepository`
- `TagRepository`
- `ChapterRepository`
- `PageOrderRepository`
- `ReaderSessionRepository`
- `RemoteMatchRepository`

Widgets must not directly implement:

- local vs remote resolution
- source/platform mutation
- page reorder validation
- candidate promotion rules

## Main Flows

### Remote Download -> Local

- resolve platform
- upsert comic
- insert source citation
- insert local library item
- generate chapters/pages
- create default page order

### User Local Import

- create comic
- record imported filename/title aliases
- insert local library item
- generate chapters/pages
- create default page order
- no confirmed source unless metadata exists

## DB Open Configuration

Canonical DB open must enable foreign keys and WAL explicitly:

```dart
Future<void> onConfigure(Database db) async {
  await db.execute('PRAGMA foreign_keys = ON');
  await db.execute('PRAGMA journal_mode = WAL');
}
```

This is required because foreign key clauses and cascade behavior are not
reliable if the connection does not enable them, and WAL should be an explicit
storage choice rather than an accidental default.

### Link Local Import -> Remote

- search candidates
- keep candidates pending until explicit acceptance
- promote accepted candidate into `comic_sources`

### Page Reorder

- validate page set
- clone active order
- write user overlay
- switch active order in one transaction

### Open Local Comic in New Tab

- create reader tab
- choose active page order
- choose local/remote load mode through repository logic

## Debug Snapshot

Add a structured reader/debug snapshot rather than relying on generic logs.

Minimum target fields:

- reader session ID
- reader tab ID
- comic ID
- load mode
- platform ID / kind
- local library item ID
- comic source ID
- current chapter/page
- page order ID / type
- page count / visible page count
- controller attached/disposed
- last error type/message

## Migration Slices

### PR1: Create `data/venera.db` foundation + DB open config

- create canonical `venera.db` schema foundation
- add DB open config with foreign keys and WAL
- add source platform tables
- add unified comic tables
- add resolver tests for canonical and legacy mapping

### PR2: Migrate `local.db`

- migrate local comic truth into `comics`, `local_library_items`, `chapters`,
  `pages`, and source-default `page_orders`
- this is a one-time breaking import into `venera.db`, not a long-lived
  compatibility bridge
- after import completes, runtime reads for migrated local comics come only from
  `venera.db`

### PR3: Migrate `history.db`

- migrate history into `history_events`
- project last-read state into reader/tab-facing read models

### PR4: Migrate `local_favorite.db`

- migrate favorite truth into canonical favorite tables or flags owned by
  `venera.db`

### PR5: Migrate source/plugin mapping

- project source/plugin mapping into `source_platforms`,
  `source_platform_aliases`, and `comic_sources`

### PR6: Finalize breaking migration contract

- old DBs are import sources only
- no runtime fallback reads from legacy DBs after migration completes
- no writes back to legacy DBs at any time in the new fork contract
- migration failure must fail loudly instead of silently continuing on legacy
  stores

### PR7: Export migration report + smoke debug snapshot

- emit migration report
- print active DB path and resolved comic/source/session state in debug snapshot

### PR8: Archive legacy DB files after verification

- move old DB files under `legacy_backup/` only after verified stable

## Acceptance

- Local comic and remote comic open through `ComicDetailPage(comicId)`
- Local imported comic has chapters/pages generated in `venera.db`
- Local favorite is not stored in `local_favorite.db` anymore
- History/last-read is not stored in `history.db` anymore
- Source citation is queryable from `venera.db`
- Tags work for both local and remote comics
- Reader tabs work for both local and remote comics
- Page reorder uses `page_orders` / `page_order_items`
- Migration is idempotent
- Old DB files are never written after migration
- Old DB files are not used as runtime fallback after migration
- Debug snapshot prints active DB path, `comicId`, `localLibraryItemId`,
  `comicSourceId`, `readerTabId`, `pageOrderId`, and `loadMode`

## Immediate Executable Slice

The first repo-grounded implementation slice should be:

1. Create canonical `data/venera.db` foundation store with open config
2. Add `source_platforms` and `source_platform_aliases`
3. Add a `SourcePlatformResolver`
4. Move favorite/history/source-key compatibility into that resolver
5. Add unified `comics`, `comic_titles`, and `local_library_items`
6. Expose a read-only `ComicDetailRepository.getComicDetail(comicId)` before
   changing the UI

This keeps the first patch narrow, testable, and aligned with the corrected
single-DB authority model instead of reinforcing the current fragmented layout.

## Breaking Change Position

This fork should treat the storage redesign as a deliberate breaking change.

Reasons:

- upstream is archived and no longer an active maintenance channel
- preserving multi-DB compatibility would make the fork carry the old authority
  split from day one
- SQLite schema reshape already requires explicit table-copy migration for
  complex changes, so pretending this can stay transparent only hides risk

Therefore:

- `local.db`, `history.db`, `local_favorite.db`, and hidden JSON domain state
  are legacy import inputs only
- the new contract is `venera.db` as sole domain authority
- migration/import is explicit, observable, and one-time
- no dual-write and no legacy fallback mode

## Non-goals

- Do not merge broad black-screen branches.
- Do not add a new state-management framework.
- Do not mutate `pages.page_index` for custom order.
- Do not store provenance only in logs.
- Do not use display name as identity.
- Do not auto-accept remote title matches.
- Do not mix user tags with source tags.
