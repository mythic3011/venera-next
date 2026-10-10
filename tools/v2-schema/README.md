# Fresh v2 SQLite reference bootstrap

This is a new greenfield reference foundation, not a compatibility layer for
the discarded runtime. The single authoritative schema remains at
docs/design/v2/02_DATABASE_SCHEMA.md; this tool extracts SQL blocks instead
of maintaining a second independent DDL copy.

The fresh-sqlite.mjs module exports loadReviewedFreshV2Sql and
initializeFreshV2Database. It installs Content/Section/Unit, source, reader,
storage, optional collection FK targets and exactly six legacy-import tables
into an EMPTY database transactionally. It rejects old-table names, checks FK
integrity, and rolls back if the schema is invalid.

Current scope is a PRE-STABLE reference baseline, not a shippable M1 Runtime:
- No Content use cases, repositories, active order completeness, media writes,
  receipts, runtime DI, native shell auth or release-schema versioning.
- Collection tables exist as FK targets for importer metadata, but M2 collection
  features and commands remain off.
- The old runtime/core physical schema (comics/chapters/pages) is quarantined
  and must not be reused, aliased or patched into a compatibility migration.
  See docs/project-direction.md. Future Native v2 must use these NEW entities.
- SQL input must come from the trusted checked-in schema design, never a
  plugin, website, old data file or arbitrary path.
- Source import inputs remain exactly five: local.db, history.db,
  local_favorite.db, appdata.json, implicitData.json. Old venera.db is excluded.

Tests: node --test tools/v2-schema/test/*.test.mjs

The new fresh-v2-schema GitHub Action executes the real SQLite tests,
including session/order uniqueness, schema drift, empty-only behavior,
transaction rollback and evidence/asset-plan-only scopes. It does not prove
full runtime readiness.
