# New v2 Runtime — Host SQLite metadata/reader foundation

This directory is an **independently written greenfield** runtime slice.
It does not import, alias, modify or migrate the discarded runtime/core
(comics, chapters, pages and reader_sessions), Dart code or old plugins.

## Runtime ownership

- src/schema-bootstrap.mjs owns the design-derived fresh schema installer.
  The single schema authority remains docs/design/v2/02_DATABASE_SCHEMA.md.
  tools/v2-schema/fresh-sqlite.mjs now re-exports the runtime installer for
  developer tests; it does not own a separate copy of the SQL schema.
- src/host-sqlite.mjs exposes a deliberately narrow trusted-host API and
  hides raw SQL and the database handle. It refuses old tables, missing
  canonical columns, absent unique indexes and disabled foreign keys.
- createTrustedInMemoryV2Runtime() produces a clean, isolated test/runtime
  instance; bindTrustedFreshV2Sqlite(db) requires a host-owned, verified DB.
  No arbitrary filename/path or untrusted IPC/RPC database opening is exposed.

## Implemented operation slice

- createContentDraft: atomically creates canonical Content,
  ContentMetadata and exactly one primary ContentTitle.
- addSectionDraft: creates a Section and image Unit **identities only**.
  Unit indexes are validated; NO storage object, media byte, thumbnail
  or available image is fabricated.
- openSection: resolves canonical units in complete active UnitOrder, or
  synthetic unit_index order ONLY when there is no active order. A
  partially populated active UnitOrder is an ERROR, never silent fallback.
- setActiveOrder: atomically replaces an active order only when every
  existing section unit is covered exactly once and none belong elsewhere.
- updateReaderPosition/getReaderPosition/clearReaderPosition: active position
  uses only the Unit ID (not a duplicated section/page field); validates
  section ownership and read-source context, keeps active session unique,
  skips unchanged writes and preserves abandoned session lifecycle rows.

These are metadata and reader persistence operations. createContentDraft and
addSectionDraft deliberately do not claim a successful media import. The
returned openSection assetStatus is unavailable until real storage policy,
verified placements and byte availability are implemented.

## Out of scope (explicitly blocked)

- File-backed host database opening / native OS path controls and production
  migration tracking; current production-app process is not wired to this API.
- Full UC-001 idempotency-key contract, full M1 import/media pipeline and
  StoragePlacements, ImportJob journal, read UI and graphics/image loading.
- Reader selection across sections, source-runtime remote fetching, hosted
  auth and multi-device synchronization.
- Native desktop shell, plugins, web routes, old-data importer Apply and
  asset stage/promote; the legacy importer still only authorizes planned
  evidence/assets with no actual copy.
- Old Runtime compatibility adapter or in-place schema migration.

CI: .github/workflows/runtime-v2-sqlite.yml
Tests: node --test runtime/v2/test/*.test.mjs

Separate CI also checks fresh-v2-schema and legacy-import-l0. Release readiness
requires stronger ports/DI boundaries, application use-case contracts,
persistent DB lifecycle, native shell integration, filesystem recovery and
real media import tests. This is a distinct M0/M1 engineering foundation,
not an end-user replacement.
