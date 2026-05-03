# Architecture Decision Record: Stop Incremental Runtime Patching

Date: 2026-05-01  
Status: Accepted

## Context

The current upstream runtime has systemic drift across reader, source resolution, history, favorites, downloads, and cache.

Observed failure pattern:
- `reader.cid` is used as both canonical identity and upstream adapter identity.
- `SourceRef` exists but legacy paths can bypass it.
- Some remote paths can pass canonical IDs (for example `remote:nhentai:646922`) into adapter-facing calls.
- Reader resume includes canonical session load mixed with legacy fallback snapshots.
- Favorites/history still include legacy identity paths while canonical sync exists.
- Schema drift exists (for example `display_order` assumptions on legacy tables).
- Unsafe null casts still exist in row/model construction.
- Cache identity semantics changed and old/new keys can diverge.
- Feature flags allow partially migrated behavior instead of one enforced contract.

Incremental patching keeps revealing new legacy escape hatches and expands regression surface.

## Decision

Stop broad incremental patching of old runtime.

Old runtime enters stabilization-only mode.  
Build a clean VeneraNext kernel with strict typed identity boundaries and fail-closed remote behavior.

## Allowed Changes in Old Runtime

1. Prevent startup crash.
2. Prevent reader crash.
3. Protect user data.
4. Export useful diagnostics.
5. Fail closed on malformed source identity.
6. Disable unsafe remote reader paths when `SourceRef` is missing/invalid.
7. Add DB backup before migration.
8. Skip legacy tables that do not satisfy required schema.
9. Replace unchecked exceptions with typed diagnostics where feasible.
10. Add tests that lock known failure modes.

## Disallowed Changes in Old Runtime

1. Add new compatibility fallbacks.
2. Accept canonical IDs inside adapter calls.
3. Rebuild upstream IDs by splitting canonical strings.
4. Let adapters receive `remote:<source>:<id>`.
5. Reuse `reader.cid` as both canonical and upstream identity.
6. Hide malformed data with nullable cast workarounds.
7. Mix legacy DB schema into canonical runtime.
8. Ship large mixed patches across reader/favorites/history/download/cache.
9. Add new feature flags toggling identity semantics.
10. Treat old cache entries as canonical truth.

## Required Boundary Model

- `CanonicalComicId`: internal runtime/session/storage identity only
- `SourceKey`: canonical source identity
- `UpstreamComicId`: adapter-facing identity
- `ChapterRefId`: adapter-facing chapter identity
- `SourceRef`: typed boundary object
- `AdapterGateway`: only layer allowed to call adapters
- `ReaderPageLoader`: page loading through `SourceRef` only
- `ReaderImageCacheKey`: explicit identity tuple

Hard rule: adapters must never receive canonical IDs.

## Fail-Closed Rule

If remote session has no valid `SourceRef`, do not infer from `reader.cid`.  
Return typed failure (`SOURCE_REF_MALFORMED` or `REMOTE_READER_REQUIRES_SOURCE_REF`) and stop before adapter/network call.

## DB Stabilization Rule

Legacy favorite/history tables are untrusted until schema-verified.

Favorite folder minimum columns:
- `id`
- `name`
- `author`
- `type`
- `tags`
- `cover_path`
- `time`
- `display_order`

Do not query `ORDER BY display_order` unless the column exists.

## Reader Stabilization Rule

Reader startup order:
1. Build + validate `SourceRef`
2. Resolve load mode
3. Resolve provider
4. Load page list
5. Validate page list
6. Sync canonical storage only after success
7. Build image providers from runtime context

Forbidden in old runtime stabilization:
- Build remote `SourceRef` from possibly canonical `reader.cid`
- Fallback from `SourceRef` upstream field to `reader.cid`
- Call adapter page load with `reader.cid`
- Sync remote pages by `reader.cid`

## Image Cache Rule

Cache keys must be structured by:
- `imageKey`
- `sourceKey`
- `canonicalComicId`
- `upstreamComicRefId`
- `chapterRefId`
- `resizeMode`

No forced null unwrap on cache lookup.

## Migration Rule

Before migration/import:
1. Copy DB backup
2. Record source/destination
3. Validate schema
4. Apply migration/import
5. Verify row counts
6. Emit diagnostics

If verification fails: stop and preserve old data.

## Test Gate (Minimum)

1. Remote reader with valid `SourceRef` passes upstream ID only.
2. Remote reader without `SourceRef` fails closed.
3. Canonical ID rejected before adapter boundary.
4. Favorite table without `display_order` is skipped or migrated before query.
5. Favorite row parsing tolerates dirty nullable rows without crash.
6. Image cache miss returns typed error.
7. Malformed remote session `SourceRef` does not call adapter.
8. Download path rejects canonical IDs before adapter call.
9. History refresh rejects canonical ID without valid `SourceRef`.
10. Source lookup rejects non-canonical source keys.

## Implementation Direction

Phase 0 - Freeze:
- stop broad runtime refactors
- add diagnostics + backup/export tooling

Phase 1 - Stabilize old runtime:
- fail-closed `SourceRef`
- reject canonical IDs before adapter calls
- verify favorite schema before query
- remove forced cache unwrap
- canonical-only source lookup
- disable unsafe legacy resolver fallback by default

Phase 2 - Build clean kernel:
- identity/
- source_ref/
- adapter/
- reader/
- cache/

Phase 3 - Port features one by one:
1. local reader
2. remote reader
3. resume session
4. image cache
5. favorites
6. history
7. downloads
8. source management

No feature ports before previous layer test gates pass.

## Consequence

Some legacy resume paths may stop working instead of guessing IDs.  
This is acceptable and preferred over incorrect upstream requests and corrupted runtime state.

