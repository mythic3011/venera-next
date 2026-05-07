# Database Schema Specification

**Language-agnostic relational schema for Venera canonical runtime.**

---

This canonical runtime schema is in pre-stable schema-definition stage. Define canonical schema directly, reset unsafe early choices when needed, and do not pay migration compatibility tax for non-stable internal data.

`normalized_title` is a matching/search signal only. It is non-unique and must never be treated as canonical comic identity authority.

This schema document is dialect-portable authority. The current `runtime/core/src/db/database.ts` SQLite path is a Node/SQLite infrastructure adapter that remains valid for local, dev, embedded, test, and temporary demo modes, while production web persistence is a future PostgreSQL-backed deployment target and must not be described as `:memory:` or demo SQLite. The current `apps/web` shell remains `demo-memory` only and intentionally non-persistent. Canonical deployment-mode rules live in `docs/design/production-database-adapter-strategy.md`.

## Table: comics

Canonical identity for comic works.

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| id | TEXT | PRIMARY KEY | Immutable UUID string |
| normalized_title | TEXT | NOT NULL | Lowercase normalized matching key (non-unique) |
| origin_hint | TEXT | NOT NULL, DEFAULT 'unknown', CHECK (origin_hint IN ('unknown', 'local', 'remote', 'mixed')) | Broad provenance hint for this comic work |
| created_at | TEXT | NOT NULL | UTC ISO string |
| updated_at | TEXT | NOT NULL | UTC ISO string |

**Indexes**:
- PRIMARY KEY `id`
- NON-UNIQUE INDEX on `normalized_title`

---

## Table: source_platforms

Source platform catalog. Declared before most other tables because many tables reference it.

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| id | TEXT | PRIMARY KEY | Immutable UUID string |
| canonical_key | TEXT | NOT NULL, UNIQUE | Stable platform key |
| display_name | TEXT | NOT NULL | User-facing name |
| kind | TEXT | NOT NULL, CHECK (kind IN ('local', 'remote', 'virtual')) | Platform kind |
| status | TEXT | NOT NULL, CHECK (status IN ('active', 'disabled', 'deprecated')) | Platform lifecycle status |
| created_at | TEXT | NOT NULL | UTC ISO string |
| updated_at | TEXT | NOT NULL | UTC ISO string |

**Indexes**:
- PRIMARY KEY `id`
- UNIQUE INDEX on `canonical_key`
- CHECK `kind IN ('local', 'remote', 'virtual')`
- CHECK `status IN ('active', 'disabled', 'deprecated')`

### Source Platform Status Transitions

Status transitions are enforced in application/domain logic, not DB triggers.

| From | To | Allowed |
|------|----|---------|
| `active` | `disabled` | Yes |
| `disabled` | `active` | Yes |
| `active` | `deprecated` | Yes |
| `disabled` | `deprecated` | Yes |
| `deprecated` | `deprecated` | Yes (no-op write) |
| `deprecated` | `active` | **Rejected** |
| `deprecated` | `disabled` | **Rejected** |

Same-state writes (e.g. `active -> active`) are allowed as no-ops. Deprecated is a terminal lifecycle state — once deprecated, a platform cannot be reactivated or re-disabled.

---

## Table: storage_backends

Storage backend catalog. Declares available backends before storage objects and placements.

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| id | TEXT | PRIMARY KEY | Immutable UUID string |
| backend_key | TEXT | NOT NULL, UNIQUE | Stable backend identifier |
| display_name | TEXT | NOT NULL | User-facing name |
| backend_kind | TEXT | NOT NULL, CHECK (backend_kind IN ('local_app_data', 'webdav', 'future')) | Backend implementation kind |
| config_json | TEXT | NOT NULL | Backend configuration payload |
| secret_ref | TEXT | NULL | Optional reference to secrets store entry |
| status | TEXT | NOT NULL, CHECK (status IN ('active', 'disabled', 'deprecated')) | Backend lifecycle status |
| created_at | TEXT | NOT NULL | UTC ISO string |
| updated_at | TEXT | NOT NULL | UTC ISO string |

**Indexes**:
- PRIMARY KEY `id`
- UNIQUE INDEX on `backend_key`
- CHECK `backend_kind IN ('local_app_data', 'webdav', 'future')`
- CHECK `status IN ('active', 'disabled', 'deprecated')`

---

## Table: storage_objects

Content-addressable storage object metadata. Represents a logical object (file) independent of where it is physically stored.

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| id | TEXT | PRIMARY KEY | Immutable UUID string |
| object_kind | TEXT | NOT NULL, CHECK (object_kind IN ('page_image', 'cover', 'archive', 'backup', 'cache')) | What kind of object this is |
| content_hash | TEXT | NULL | Content hash for deduplication/verification |
| size_bytes | INTEGER | NULL | Object size in bytes |
| mime_type | TEXT | NULL | MIME type of the content |
| created_at | TEXT | NOT NULL | UTC ISO string |
| updated_at | TEXT | NOT NULL | UTC ISO string |

**Indexes**:
- PRIMARY KEY `id`
- CHECK `object_kind IN ('page_image', 'cover', 'archive', 'backup', 'cache')`

---

## Table: chapters

Ordered chapter sequence inside a comic. Supports nesting via `parent_chapter_id` for season/volume groupings.

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| id | TEXT | PRIMARY KEY | Immutable UUID string |
| comic_id | TEXT | NOT NULL, FK(comics.id) ON DELETE CASCADE | Parent comic; immutable |
| parent_chapter_id | TEXT | NULL, FK(chapters.id) ON DELETE SET NULL | Optional parent chapter for nested groupings |
| chapter_kind | TEXT | NOT NULL, CHECK (chapter_kind IN ('season', 'volume', 'chapter', 'episode', 'oneshot', 'group')) | Structural kind of this chapter node |
| chapter_number | REAL | NULL | Optional ordering hint (1.0, 1.5, 2.0…). Non-unique, non-identity. |
| title | TEXT | NULL | Optional chapter name |
| display_label | TEXT | NULL | Optional display label; may differ from title |
| created_at | TEXT | NOT NULL | UTC ISO string |
| updated_at | TEXT | NOT NULL | UTC ISO string |

**Indexes**:
- PRIMARY KEY `id`
- INDEX on `comic_id`
- INDEX on `parent_chapter_id`
- Foreign key `(comic_id) REFERENCES comics(id) ON DELETE CASCADE`
- Foreign key `(parent_chapter_id) REFERENCES chapters(id) ON DELETE SET NULL`
- CHECK `chapter_kind IN ('season', 'volume', 'chapter', 'episode', 'oneshot', 'group')`

**Notes**:
- `chapter_number` is nullable, non-unique, and never treated as an identity field. Multiple chapters may share the same `chapter_number` (e.g. split releases or decimal chapters).
- `parent_chapter_id` enables season/volume grouping without a separate grouping table.

---

## Table: source_links

Comic-level source provenance links (multi-source capable). This table replaces the old `comic_source_links` table.

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| id | TEXT | PRIMARY KEY | Immutable UUID string |
| comic_id | TEXT | NOT NULL, FK(comics.id) ON DELETE CASCADE | Canonical comic |
| source_platform_id | TEXT | NOT NULL, FK(source_platforms.id) ON DELETE RESTRICT | Source platform |
| remote_work_id | TEXT | NOT NULL | Source-side work identifier |
| remote_url | TEXT | NULL | Sanitized remote URL evidence |
| display_title | TEXT | NULL | Source-provided display title evidence |
| link_status | TEXT | NOT NULL, CHECK (link_status IN ('active', 'candidate', 'rejected', 'stale')) | Link lifecycle status |
| confidence | TEXT | NOT NULL, CHECK (confidence IN ('manual', 'auto_high', 'auto_low')) | Confidence level of this link mapping |
| created_at | TEXT | NOT NULL | UTC ISO string |
| updated_at | TEXT | NOT NULL | UTC ISO string |

**Indexes**:
- PRIMARY KEY `id`
- UNIQUE INDEX on `(source_platform_id, remote_work_id)`
- INDEX on `comic_id`
- Foreign key `(comic_id) REFERENCES comics(id) ON DELETE CASCADE`
- Foreign key `(source_platform_id) REFERENCES source_platforms(id) ON DELETE RESTRICT`
- CHECK `link_status IN ('active', 'candidate', 'rejected', 'stale')`
- CHECK `confidence IN ('manual', 'auto_high', 'auto_low')`

---

## Table: chapter_source_links

Chapter-level source provenance links.

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| id | TEXT | PRIMARY KEY | Immutable UUID string |
| chapter_id | TEXT | NOT NULL, FK(chapters.id) ON DELETE CASCADE | Canonical chapter |
| source_link_id | TEXT | NOT NULL, FK(source_links.id) ON DELETE CASCADE | Parent comic source link |
| remote_chapter_id | TEXT | NOT NULL | Source-side chapter identifier |
| remote_url | TEXT | NULL | Sanitized source URL |
| remote_label | TEXT | NULL | Source-provided chapter label evidence |
| source_order | INTEGER | NULL | Source-provided ordering hint |
| link_status | TEXT | NOT NULL, CHECK (link_status IN ('active', 'inactive', 'stale')) | Link lifecycle status |
| created_at | TEXT | NOT NULL | UTC ISO string |
| updated_at | TEXT | NOT NULL | UTC ISO string |

**Indexes**:
- PRIMARY KEY `id`
- UNIQUE INDEX on `(source_link_id, remote_chapter_id)`
- INDEX on `chapter_id`
- Foreign key `(chapter_id) REFERENCES chapters(id) ON DELETE CASCADE`
- Foreign key `(source_link_id) REFERENCES source_links(id) ON DELETE CASCADE`
- CHECK `link_status IN ('active', 'inactive', 'stale')`

**Source order aggregation**: The canonical display order for a chapter derived from source is `MIN(source_order)` across active chapter source links with non-null `source_order`. Active chapter source links are those with `link_status = 'active'` and whose parent `source_platforms.status = 'active'`. If no active links with a non-null `source_order` exist, source order is absent.

---

## Table: pages

Ordered pages inside a chapter.

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| id | TEXT | PRIMARY KEY | Immutable UUID string |
| chapter_id | TEXT | NOT NULL, FK(chapters.id) ON DELETE CASCADE | Parent chapter; immutable |
| page_index | INTEGER | NOT NULL | 0-based contiguous index |
| storage_object_id | TEXT | NULL, FK(storage_objects.id) ON DELETE SET NULL | Optional storage object reference |
| chapter_source_link_id | TEXT | NULL, FK(chapter_source_links.id) ON DELETE SET NULL | Optional source link that provided this page |
| mime_type | TEXT | NULL | MIME type hint |
| width | INTEGER | NULL | Image width in pixels |
| height | INTEGER | NULL | Image height in pixels |
| checksum | TEXT | NULL | Content checksum |
| created_at | TEXT | NOT NULL | UTC ISO string |
| updated_at | TEXT | NOT NULL | UTC ISO string |

**Indexes**:
- PRIMARY KEY `id`
- UNIQUE INDEX on `(chapter_id, page_index)` — enforces contiguous, non-duplicate page positions within a chapter
- INDEX on `storage_object_id`
- INDEX on `chapter_source_link_id`
- Foreign key `(chapter_id) REFERENCES chapters(id) ON DELETE CASCADE`
- Foreign key `(storage_object_id) REFERENCES storage_objects(id) ON DELETE SET NULL`
- Foreign key `(chapter_source_link_id) REFERENCES chapter_source_links(id) ON DELETE SET NULL`

---

## Table: comic_metadata

Mutable comic properties. `title` is an intentionally denormalized cache and MUST equal the current `comic_titles` primary title for this comic.

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| comic_id | TEXT | PRIMARY KEY, FK(comics.id) ON DELETE CASCADE | One-to-one with comics |
| title | TEXT | NOT NULL | Denormalized cache of the current primary title. Must equal the `comic_titles` row with `title_kind = 'primary'` for this comic. |
| description | TEXT | NULL | Optional long description |
| cover_page_id | TEXT | NULL, FK(pages.id) ON DELETE SET NULL | Optional cover page reference |
| cover_storage_object_id | TEXT | NULL, FK(storage_objects.id) ON DELETE SET NULL | Optional storage object reference for cover |
| author_name | TEXT | NULL | Optional author name |
| metadata_json | TEXT | NULL | Optional structured metadata payload |
| created_at | TEXT | NOT NULL | UTC ISO string |
| updated_at | TEXT | NOT NULL | UTC ISO string |

**Indexes**:
- PRIMARY KEY `comic_id`
- Foreign key `(comic_id) REFERENCES comics(id) ON DELETE CASCADE`
- Foreign key `(cover_page_id) REFERENCES pages(id) ON DELETE SET NULL`
- Foreign key `(cover_storage_object_id) REFERENCES storage_objects(id) ON DELETE SET NULL`

**Invariant**: `comic_metadata.title` must always equal the `title` of the `comic_titles` row for this comic where `title_kind = 'primary'`. Any mutation that changes the primary title must update both records atomically.

---

## Table: comic_titles

Canonical title records separating primary and provenance title evidence.

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| id | TEXT | PRIMARY KEY | UUID v4 string or deterministic key |
| comic_id | TEXT | NOT NULL, FK(comics.id) ON DELETE CASCADE | Parent comic |
| title | TEXT | NOT NULL | Raw title text |
| normalized_title | TEXT | NOT NULL | Non-unique matching signal |
| locale | TEXT | NULL | BCP-47 locale tag or NULL |
| source_platform_id | TEXT | NULL, FK(source_platforms.id) ON DELETE SET NULL | Optional provenance reference |
| source_link_id | TEXT | NULL, FK(source_links.id) ON DELETE SET NULL | Optional source link provenance |
| title_kind | TEXT | NOT NULL, CHECK (title_kind IN ('primary', 'source', 'alias')) | Title kind |
| created_at | TEXT | NOT NULL | UTC ISO string |

**Indexes**:
- PRIMARY KEY `id`
- INDEX on `comic_id`
- INDEX on `normalized_title`
- INDEX on `(comic_id, title_kind)`
- UNIQUE INDEX on `(comic_id, normalized_title, locale, source_platform_id)` — prevents duplicate title evidence per locale/platform combination
- PARTIAL UNIQUE INDEX on `(comic_id)` WHERE `title_kind = 'primary'` — enforces exactly one primary title per comic
- Foreign key `(comic_id) REFERENCES comics(id) ON DELETE CASCADE`
- Foreign key `(source_platform_id) REFERENCES source_platforms(id) ON DELETE SET NULL`
- Foreign key `(source_link_id) REFERENCES source_links(id) ON DELETE SET NULL`
- CHECK `title_kind IN ('primary', 'source', 'alias')`

**Notes**:
- `title_kind` values: `primary` (the user-facing canonical title), `source` (evidence from a source platform), `alias` (alternate known title).
- Exactly one `primary` title per comic is enforced by the partial unique index `ux_comic_titles_one_primary`.

---

## Table: page_orders

Named page-order profiles for a chapter. One active order per chapter is enforced by a partial unique index.

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| id | TEXT | PRIMARY KEY | UUID v4 string |
| chapter_id | TEXT | NOT NULL, FK(chapters.id) ON DELETE CASCADE | Parent chapter |
| order_key | TEXT | NOT NULL, CHECK (order_key IN ('source', 'user', 'import_detected', 'custom')) | Order key identifying the profile kind |
| order_type | TEXT | NOT NULL, CHECK (order_type IN ('source', 'user_override', 'import_detected', 'custom')) | Semantic order type |
| is_active | INTEGER | NOT NULL, CHECK (is_active IN (0, 1)) | 1 = active profile for the chapter; 0 = inactive |
| page_count | INTEGER | NOT NULL | Total pages in this order profile |
| created_at | TEXT | NOT NULL | UTC ISO string |
| updated_at | TEXT | NOT NULL | UTC ISO string |

**Indexes**:
- PRIMARY KEY `id`
- INDEX on `chapter_id`
- PARTIAL UNIQUE INDEX on `(chapter_id)` WHERE `is_active = 1` — enforces at most one active order per chapter
- Foreign key `(chapter_id) REFERENCES chapters(id) ON DELETE CASCADE`
- CHECK `order_key IN ('source', 'user', 'import_detected', 'custom')`
- CHECK `order_type IN ('source', 'user_override', 'import_detected', 'custom')`
- CHECK `is_active IN (0, 1)`

---

## Table: page_order_items

Normalized item-level ordering for page-order profiles.

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| id | TEXT | PRIMARY KEY | UUID v4 string |
| page_order_id | TEXT | NOT NULL, FK(page_orders.id) ON DELETE CASCADE | Parent order profile |
| page_id | TEXT | NOT NULL, FK(pages.id) ON DELETE CASCADE | Referenced page |
| sort_index | INTEGER | NOT NULL | Explicit 0-based sort position |
| created_at | TEXT | NOT NULL | UTC ISO string |

**Indexes**:
- PRIMARY KEY `id`
- UNIQUE INDEX on `(page_order_id, sort_index)` — no two items share the same position in an order
- UNIQUE INDEX on `(page_order_id, page_id)` — a page appears at most once per order profile
- Foreign key `(page_order_id) REFERENCES page_orders(id) ON DELETE CASCADE`
- Foreign key `(page_id) REFERENCES pages(id) ON DELETE CASCADE`

---

## Table: storage_placements

Physical placement of a storage object on a specific backend. A single storage object may have multiple placements across backends with different roles.

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| id | TEXT | PRIMARY KEY | Immutable UUID string |
| storage_object_id | TEXT | NOT NULL, FK(storage_objects.id) ON DELETE CASCADE | Parent storage object |
| storage_backend_id | TEXT | NOT NULL, FK(storage_backends.id) ON DELETE RESTRICT | Target backend |
| object_key | TEXT | NOT NULL | Backend-relative key/path for this object |
| role | TEXT | NOT NULL, CHECK (role IN ('authority', 'cache', 'mirror', 'staging')) | Role of this placement |
| sync_status | TEXT | NOT NULL, CHECK (sync_status IN ('pending', 'uploading', 'synced', 'failed', 'evicted')) | Current sync state |
| last_verified_at | TEXT | NULL | Last verification timestamp; NULL = never verified |
| created_at | TEXT | NOT NULL | UTC ISO string |
| updated_at | TEXT | NOT NULL | UTC ISO string |

**Indexes**:
- PRIMARY KEY `id`
- Foreign key `(storage_object_id) REFERENCES storage_objects(id) ON DELETE CASCADE`
- Foreign key `(storage_backend_id) REFERENCES storage_backends(id) ON DELETE RESTRICT`
- CHECK `role IN ('authority', 'cache', 'mirror', 'staging')`
- CHECK `sync_status IN ('pending', 'uploading', 'synced', 'failed', 'evicted')`

---

## Table: reader_sessions

Current Core+DB reader position state. One session per comic.

The saved reader position authority is `chapter_id + page_index`. `page_id` is optional evidence/cache.

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| id | TEXT | PRIMARY KEY | Immutable UUID string |
| comic_id | TEXT | NOT NULL, UNIQUE, FK(comics.id) ON DELETE CASCADE | One session per comic |
| chapter_id | TEXT | NOT NULL, FK(chapters.id) ON DELETE CASCADE | Current chapter |
| page_id | TEXT | NULL, FK(pages.id) ON DELETE SET NULL | Optional page identity cache |
| page_index | INTEGER | NOT NULL | Current page index (position authority) |
| created_at | TEXT | NOT NULL | UTC ISO string |
| updated_at | TEXT | NOT NULL | UTC ISO string |

**Indexes**:
- PRIMARY KEY `id`
- UNIQUE INDEX on `comic_id`
- Foreign key `(comic_id) REFERENCES comics(id) ON DELETE CASCADE`
- Foreign key `(chapter_id) REFERENCES chapters(id) ON DELETE CASCADE`
- Foreign key `(page_id) REFERENCES pages(id) ON DELETE SET NULL`

**Position authority rules**:
- The authoritative saved position is `chapter_id + page_index`.
- `page_id`, when present, is optional evidence that must be consistent: if `page_id` is set, it must point to a page in `chapter_id` whose `page_index` equals `reader_sessions.page_index`. If this invariant is violated, the saved session is invalid.
- `page_id` may be NULL without invalidating the session.

---

## Table: operation_idempotency

Idempotency ledger for mutation workflows.

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| operation_name | TEXT | NOT NULL | e.g., `CreateCanonicalComic` |
| idempotency_key | TEXT | NOT NULL | Caller key (operation-scoped namespace) |
| input_hash | TEXT | NOT NULL | Canonical input hash |
| status | TEXT | NOT NULL, CHECK (status IN ('in_progress', 'completed', 'failed')) | Current operation status |
| result_type | TEXT | NULL | Result discriminator for replay |
| result_resource_id | TEXT | NULL | Primary resource identifier for replay |
| result_json | TEXT | NULL | Serialized replay payload |
| result_schema_version | TEXT | NULL | Replay payload schema version |
| created_at | TEXT | NOT NULL | UTC ISO string |
| updated_at | TEXT | NOT NULL | UTC ISO string |

**Indexes**:
- PRIMARY KEY `(operation_name, idempotency_key)` — composite; scopes idempotency keys per operation
- INDEX on `(operation_name, created_at)`
- CHECK `status IN ('in_progress', 'completed', 'failed')`

**Backlog**: Idempotency TTL cleanup is not implemented. TODO: implement periodic cleanup of stale `in_progress` and `failed` records.

---

## Table: diagnostics_events

Persisted diagnostics evidence with explicit schema version.

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| id | TEXT | PRIMARY KEY | UUID v4 |
| schema_version | TEXT | NOT NULL, DEFAULT '1.0.0' | Diagnostics schema version |
| timestamp | TEXT | NOT NULL | UTC ISO string |
| level | TEXT | NOT NULL, CHECK (level IN ('trace', 'info', 'warn', 'error')) | Log level |
| channel | TEXT | NOT NULL | Diagnostic channel name |
| event_name | TEXT | NOT NULL | Namespaced event name |
| correlation_id | TEXT | NULL | Optional trace/correlation ID |
| boundary | TEXT | NULL | Optional boundary context |
| action | TEXT | NULL | Optional action label |
| authority | TEXT | NULL, CHECK (authority IN ('canonical_db', 'storage', 'source_runtime', 'unknown')) | Optional authority context |
| comic_id | TEXT | NULL, FK(comics.id) ON DELETE SET NULL | Optional associated comic |
| source_platform_id | TEXT | NULL, FK(source_platforms.id) ON DELETE SET NULL | Optional associated source platform |
| payload_json | TEXT | NOT NULL | Sanitized JSON event payload |

**Indexes**:
- PRIMARY KEY `id`
- INDEX on `timestamp`
- INDEX on `(level, timestamp)`
- INDEX on `correlation_id`
- INDEX on `event_name`
- Foreign key `(comic_id) REFERENCES comics(id) ON DELETE SET NULL`
- Foreign key `(source_platform_id) REFERENCES source_platforms(id) ON DELETE SET NULL`
- CHECK `level IN ('trace', 'info', 'warn', 'error')`
- CHECK `authority IN ('canonical_db', 'storage', 'source_runtime', 'unknown')` (nullable)

---

## Removed Tables (Not in Current Core Pass)

The following tables are **not present** in the current canonical schema pass and must not be referenced as current authority:

- **`page_source_links`** — page-level source links are deferred. No `page_source_links` table exists in the current schema.
- **`favorites`** — no favorites table in the current core pass. Source account favorite state is evidence on `source_links`; local favorite authority is deferred.
- **`import_batches`** — no import batch tracking table in the current core pass.

---

## Remote Detail Payload Mapping

Legacy source models expose rich remote detail payloads such as title, subtitle, cover, description, grouped chapters, tags, thumbnails, recommendations, favorite state, likes, comment counts, uploader, upload/update time, URL, stars, max-page hints, and comments.

Canonical DB must not store those payloads as a raw source runtime object.

They should be split by authority:

| Legacy detail field | Canonical direction | Authority note |
|---|---|---|
| `title` | `comic_metadata.title`, `comic_titles`, `source_links.display_title` | User title and source title evidence are separate |
| `subTitle` | `source_links.display_title` (evidence) | Source evidence only |
| `cover` | `comic_metadata.cover_page_id`, `comic_metadata.cover_storage_object_id`, storage pipeline | URL evidence is not storage authority |
| `description` | `comic_metadata.description` | User-facing metadata may diverge from source evidence |
| `tags: Map<String, List<String>>` | `source_tags`, `comic_source_link_tags`, `tag_mappings`, `canonical_tags` | Preserve namespace/value provenance before canonical mapping |
| `chapters` | `chapter_source_links` plus canonical `chapters` | Grouped/flat source chapters are provenance, not canonical chapter identity by themselves |
| `thumbnails` | future remote media evidence or source metadata JSON | Not page authority |
| `recommend` | future recommendation cache/provenance | Not canonical relationship authority in this schema |
| `isFavorite`, `favoriteId` | source/account provenance on `source_links` | Must not replace local favorites authority (deferred) |
| `isLiked`, `likesCount`, `commentCount`, `comments` | future remote social/comment evidence | Deferred; not V1 local metadata authority |
| `uploader` | `source_links` metadata_json or future field | Source evidence only |
| `uploadTime` | `source_links` metadata_json or future field | Source evidence only |
| `updateTime` | `source_links` metadata_json or future field | Source evidence only |
| `url` | `source_links.remote_url` | Sanitized source URL evidence |
| `stars` | future source evidence field | Source rating evidence only |
| `maxPage` | not stored; actual pages are canonical rows | Hint only; dropped from current schema |
| `sourceKey`, `comicId`, `subId` | `source_platforms.canonical_key`, `source_links.remote_work_id` | Provider identity must be canonicalized before storage |

Rules:

```text
Remote detail payloads are source evidence, not canonical identity.
Source account state such as favorite/liked status does not mutate local favorites.
Comment/like/rating data is deferred remote social evidence, not local metadata authority.
Grouped source chapters must be recorded as provenance and mapped into canonical chapters explicitly.
Raw sourceKey@id, plainTags, and page-jump encodings must not become canonical DB identity.
```

---

## Table Direction: Canonical/Source/User Tags

Use normalized tag-layering instead of untyped tag clouds.

Recommended table direction:
- `canonical_tags` and `tag_labels` (canonical taxonomy authority)
- `source_tags` (remote/source raw tags)
- `tag_mappings` (source-to-canonical mapping)
- `comic_source_link_tags` (tag evidence per source link)
- `user_tags` and `comic_user_tags` (user annotations)

Provider-specific special tables (for example `eh_tag_taxonomy`) are legacy-only and not canonical table authority.

---

## Table: source_manifests

**Status**: Deferred/Legacy placeholder (not canonical V1 authority).

Legacy single-manifest/provider payload model is retained only as historical context.
Canonical direction is:

`repository index -> package manifest -> integrity verifier -> package store -> source_platform mutation`

Do not treat this legacy table as canonical source package authority.

---

## Table Direction: Source Package Boundaries (Future)

Future direction only (final schema intentionally deferred):
- `source_repositories` (repository index/trust metadata)
- `source_repository_packages` (repository listing/cache only)
- `source_package_artifacts` (durable verified artifact metadata; PackageStore-aligned boundary)

Do not reintroduce loose runtime identity fields as authority (for example `source_ref_json`, loose `source_key`, filesystem path identity).

---

## Transaction Semantics

### Atomic Operations

1. **Create Comic with Metadata**:
   - Claim/replay idempotency inside the same transaction when idempotency key is provided
   - On replay hit with same `input_hash`: return stored completed result
   - On same `(operation_name, idempotency_key)` with different `input_hash`: return `IDEMPOTENCY_CONFLICT` (fail closed, no mutation)
   - INSERT into `comics`
   - INSERT into `comic_metadata`
   - INSERT canonical primary title record into `comic_titles` (with `title_kind = 'primary'`)
   - `comic_metadata.title` must equal the `comic_titles` primary title; both are written in the same transaction
   - Record completed idempotency result only after canonical writes succeed
   - No implicit `reader_sessions` creation at comic create time
   - All writes succeed or all rollback

2. **Create Chapter with Pages**:
   - INSERT into `chapters`
   - INSERT into `pages`
   - INSERT into `page_orders` and `page_order_items` (default source order)
   - All writes succeed or all rollback

3. **Update Reader Position**:
   - UPDATE `reader_sessions`
   - No favorite coupling in current core contract
   - Write scope stays within reader session persistence boundary

### Concurrency

- Reader position is last-write-wins.
- Chapter/page creation is serialized per comic.
- Source-link mutation is serialized per affected source link scope.

---

## Legacy Guardrails (Non-Authority)

The following legacy patterns are not canonical DB authority and must not be promoted:
- `source_platform_aliases`
- `is_enabled` (replaced by `status` enum)
- provider/display-name identity matching
- filesystem authority fields (`cover_local_path`, `local_path`, `local_root_path`, `imported_from_path`)
- `source_ref_json` as runtime identity
- loose `source_key` identity
- provider-specific special taxonomy tables as core authority
- `comic_source_links` table name (replaced by `source_links`)
- `title_type` column name (replaced by `title_kind`)
- `active_tab_position` on reader sessions (removed)
- `max_page_hint` and `tags_ref` on comic_metadata (removed)
- `order_name` / `normalized_order_name` on page_orders (replaced by `order_key`)
- `sort_order` on page_order_items (replaced by `sort_index`)
- `is_hidden` on page_order_items (removed)

---

## Migration/Backup Scope

- Pre-stable schema can be reset without compatibility guarantees.
- Legacy data movement is deferred adapter/import boundary work, not canonical DB migration contract.
- Backup/recovery strategy is deployment/infra policy and out of scope here.
- This document does not promise transaction-log shipping or PITR.
