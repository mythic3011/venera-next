# Database Schema Specification

**Language-agnostic relational schema for Venera canonical runtime.**

---

This canonical runtime schema is in pre-stable schema-definition stage. Define canonical schema directly, reset unsafe early choices when needed, and do not pay migration compatibility tax for non-stable internal data.

`normalized_title` is a matching/search signal only. It is non-unique and must never be treated as canonical comic identity authority.

## Table: comics

Canonical identity for comic works.

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| id | UUID | PRIMARY KEY | Immutable |
| normalized_title | TEXT | NOT NULL | Lowercase normalized matching key (non-unique) |
| created_at | TIMESTAMP | NOT NULL, DEFAULT CURRENT_TIMESTAMP | UTC |
| updated_at | TIMESTAMP | NOT NULL, DEFAULT CURRENT_TIMESTAMP | UTC |

**Indexes**:
- PRIMARY KEY `id`
- NON-UNIQUE INDEX on `normalized_title`

---

## Table: comic_metadata

Mutable comic properties.

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| comic_id | UUID | PRIMARY KEY, FK(comics.id) | Immutable |
| title | TEXT | NOT NULL | User-facing title |
| description | TEXT | NULL | Optional long text |
| cover_storage_object_id | TEXT | NULL | Optional storage object reference |
| author_name | TEXT | NULL | Optional |
| max_page_hint | INTEGER | NULL | Optional source/detail hint, not page authority |
| tags_ref | TEXT | NULL | Transitional read-model pointer only; not canonical tag storage authority |

**Indexes**:
- PRIMARY KEY `comic_id`
- Foreign key `(comic_id) REFERENCES comics(id) ON DELETE CASCADE`

---

## Table: comic_titles

Canonical title records separating primary and provenance title evidence.

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| id | TEXT | PRIMARY KEY | UUID v4 string or deterministic key |
| comic_id | UUID | NOT NULL, FK(comics.id) | Parent comic |
| title | TEXT | NOT NULL | Raw title text |
| normalized_title | TEXT | NOT NULL | Non-unique matching signal |
| title_type | VARCHAR(20) | NOT NULL | `primary`, `source`, `alias` |
| source_platform_id | UUID | NULL, FK(source_platforms.id) | Optional provenance reference |
| created_at | TIMESTAMP | NOT NULL, DEFAULT CURRENT_TIMESTAMP | UTC |

**Indexes**:
- PRIMARY KEY `id`
- INDEX on `comic_id`
- INDEX on `normalized_title`
- INDEX on `(comic_id, title_type)`
- UNIQUE INDEX on `(comic_id)` WHERE `title_type = 'primary'`
- Foreign key `(comic_id) REFERENCES comics(id) ON DELETE CASCADE`
- Foreign key `(source_platform_id) REFERENCES source_platforms(id) ON DELETE SET NULL`
- CHECK `title_type IN ('primary', 'source', 'alias')`

---

## Table: chapters

Ordered chapter sequence inside a comic.

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| id | UUID | PRIMARY KEY | Immutable |
| comic_id | UUID | NOT NULL, FK(comics.id) | Immutable |
| chapter_number | FLOAT | NULL | Optional ordering hint (1.0, 1.5, 2.0...) |
| title | TEXT | NULL | Optional chapter name |
| created_at | TIMESTAMP | NOT NULL, DEFAULT CURRENT_TIMESTAMP | UTC |
| updated_at | TIMESTAMP | NOT NULL, DEFAULT CURRENT_TIMESTAMP | UTC |

**Indexes**:
- PRIMARY KEY `id`
- INDEX on `(comic_id, chapter_number)`
- INDEX on `(comic_id, created_at, id)`
- Foreign key `(comic_id) REFERENCES comics(id) ON DELETE CASCADE`

---

## Table: pages

Ordered pages inside a chapter.

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| id | UUID | PRIMARY KEY | Immutable |
| chapter_id | UUID | NOT NULL, FK(chapters.id) | Immutable |
| page_index | INTEGER | NOT NULL | 0-based contiguous index |
| storage_object_id | TEXT | NULL | Optional storage object reference |
| created_at | TIMESTAMP | NOT NULL, DEFAULT CURRENT_TIMESTAMP | UTC |
| updated_at | TIMESTAMP | NOT NULL, DEFAULT CURRENT_TIMESTAMP | UTC |

**Indexes**:
- PRIMARY KEY `id`
- UNIQUE INDEX on `(chapter_id, page_index)`
- Foreign key `(chapter_id) REFERENCES chapters(id) ON DELETE CASCADE`

---

## Table: page_orders

Named page-order profiles for a chapter.

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| id | TEXT | PRIMARY KEY | UUID v4 string |
| chapter_id | UUID | NOT NULL, FK(chapters.id) | Parent chapter |
| order_name | TEXT | NOT NULL | User-facing order name |
| normalized_order_name | TEXT | NOT NULL | Normalized name for matching |
| order_type | VARCHAR(20) | NOT NULL | `source`, `user_override`, `import_detected` |
| is_active | BOOLEAN | NOT NULL, DEFAULT FALSE | Active profile for the chapter |
| created_at | TIMESTAMP | NOT NULL, DEFAULT CURRENT_TIMESTAMP | UTC |
| updated_at | TIMESTAMP | NOT NULL, DEFAULT CURRENT_TIMESTAMP | UTC |

**Indexes**:
- PRIMARY KEY `id`
- INDEX on `chapter_id`
- UNIQUE INDEX on `(chapter_id)` WHERE `is_active = TRUE`
- UNIQUE INDEX on `(chapter_id, normalized_order_name)`
- Foreign key `(chapter_id) REFERENCES chapters(id) ON DELETE CASCADE`
- CHECK `order_type IN ('source', 'user_override', 'import_detected')`

---

## Table: page_order_items

Normalized item-level ordering for page-order profiles.

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| page_order_id | TEXT | NOT NULL, FK(page_orders.id) | Parent order profile |
| page_id | UUID | NOT NULL, FK(pages.id) | Referenced page |
| sort_order | INTEGER | NOT NULL | Explicit order index |
| is_hidden | BOOLEAN | NOT NULL, DEFAULT FALSE | Hidden within this order profile |
| added_at | TIMESTAMP | NOT NULL, DEFAULT CURRENT_TIMESTAMP | UTC |

**Indexes**:
- UNIQUE INDEX on `(page_order_id, page_id)`
- UNIQUE INDEX on `(page_order_id, sort_order)`
- INDEX on `(page_order_id, is_hidden)`
- Foreign key `(page_order_id) REFERENCES page_orders(id) ON DELETE CASCADE`
- Foreign key `(page_id) REFERENCES pages(id) ON DELETE CASCADE`

---

## Table: reader_sessions

Current Core+DB reader position state.

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| id | UUID | PRIMARY KEY | Immutable |
| comic_id | UUID | NOT NULL, UNIQUE, FK(comics.id) | One per comic |
| chapter_id | UUID | NOT NULL, FK(chapters.id) | Current chapter |
| page_index | INTEGER | NOT NULL | Current page index |
| active_tab_position | INTEGER | NOT NULL, DEFAULT 0 | Reserved compatibility field; multi-tab model is deferred |
| created_at | TIMESTAMP | NOT NULL, DEFAULT CURRENT_TIMESTAMP | UTC |
| updated_at | TIMESTAMP | NOT NULL, DEFAULT CURRENT_TIMESTAMP | UTC |

**Indexes**:
- PRIMARY KEY `id`
- UNIQUE INDEX on `comic_id`
- Foreign key `(comic_id) REFERENCES comics(id) ON DELETE CASCADE`
- Foreign key `(chapter_id) REFERENCES chapters(id) ON DELETE RESTRICT`

---

## Table: source_platforms

Source platform catalog.

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| id | UUID | PRIMARY KEY | Immutable |
| canonical_key | TEXT | NOT NULL, UNIQUE | Stable platform key |
| display_name | TEXT | NOT NULL | User-facing name |
| kind | VARCHAR(20) | NOT NULL | `local`, `remote`, `virtual` |
| status | VARCHAR(20) | NOT NULL, DEFAULT 'active' | `active`, `disabled`, `deprecated` |
| created_at | TIMESTAMP | NOT NULL, DEFAULT CURRENT_TIMESTAMP | UTC |
| updated_at | TIMESTAMP | NOT NULL, DEFAULT CURRENT_TIMESTAMP | UTC |

**Indexes**:
- PRIMARY KEY `id`
- UNIQUE INDEX on `canonical_key`
- CHECK `kind IN ('local', 'remote', 'virtual')`
- CHECK `status IN ('active', 'disabled', 'deprecated')`

---

## Table: comic_source_links

Comic-level source provenance links (multi-source capable).

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| id | TEXT | PRIMARY KEY | UUID v4 string |
| comic_id | UUID | NOT NULL, FK(comics.id) | Canonical comic |
| source_platform_id | UUID | NOT NULL, FK(source_platforms.id) | Source platform |
| source_comic_id | TEXT | NOT NULL | Source-side comic identifier |
| link_status | VARCHAR(20) | NOT NULL, DEFAULT 'active' | active/inactive/stale |
| is_primary | BOOLEAN | NOT NULL, DEFAULT FALSE | Preferred source link |
| source_url | TEXT | NULL | Sanitized source URL |
| source_title | TEXT | NULL | Source title evidence |
| source_subtitle | TEXT | NULL | Source subtitle evidence |
| source_cover_url | TEXT | NULL | Sanitized remote cover URL evidence |
| source_description | TEXT | NULL | Source description evidence |
| source_language | TEXT | NULL | Source language evidence |
| source_uploader | TEXT | NULL | Source uploader evidence |
| source_upload_time | TEXT | NULL | Source upload time evidence |
| source_update_time | TEXT | NULL | Source update time evidence |
| source_stars | FLOAT | NULL | Source rating evidence |
| source_max_page | INTEGER | NULL | Source max-page hint |
| source_sub_id | TEXT | NULL | Provider-specific sub identifier |
| source_favorite_id | TEXT | NULL | Provider favorite identifier/provenance |
| remote_favorite_state | VARCHAR(20) | NULL | Provider account evidence only; not local favorite authority |
| metadata_json | TEXT | NULL | Sanitized provenance payload |
| linked_at | TIMESTAMP | NOT NULL, DEFAULT CURRENT_TIMESTAMP | UTC |
| updated_at | TIMESTAMP | NOT NULL, DEFAULT CURRENT_TIMESTAMP | UTC |

**Indexes**:
- UNIQUE INDEX on `(source_platform_id, source_comic_id)`
- INDEX on `comic_id`
- INDEX on `(comic_id, is_primary)`
- Foreign key `(comic_id) REFERENCES comics(id) ON DELETE CASCADE`
- Foreign key `(source_platform_id) REFERENCES source_platforms(id) ON DELETE CASCADE`

---

## Table: chapter_source_links

Chapter-level source provenance links.

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| id | TEXT | PRIMARY KEY | UUID v4 string |
| chapter_id | UUID | NOT NULL, FK(chapters.id) | Canonical chapter |
| comic_source_link_id | TEXT | NOT NULL, FK(comic_source_links.id) | Parent comic source link |
| source_chapter_id | TEXT | NOT NULL | Source-side chapter identifier |
| source_group_name | TEXT | NULL | Source grouped-chapter name evidence |
| source_title | TEXT | NULL | Source chapter title evidence |
| source_order | INTEGER | NULL | Source-provided ordering hint |
| source_url | TEXT | NULL | Sanitized source URL |
| metadata_json | TEXT | NULL | Sanitized provenance payload |
| linked_at | TIMESTAMP | NOT NULL, DEFAULT CURRENT_TIMESTAMP | UTC |
| updated_at | TIMESTAMP | NOT NULL, DEFAULT CURRENT_TIMESTAMP | UTC |

**Indexes**:
- UNIQUE INDEX on `(comic_source_link_id, source_chapter_id)`
- INDEX on `chapter_id`
- Foreign key `(chapter_id) REFERENCES chapters(id) ON DELETE CASCADE`
- Foreign key `(comic_source_link_id) REFERENCES comic_source_links(id) ON DELETE CASCADE`

---

## Table: page_source_links

Page-level source provenance links.

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| id | TEXT | PRIMARY KEY | UUID v4 string |
| page_id | UUID | NOT NULL, FK(pages.id) | Canonical page |
| comic_source_link_id | TEXT | NOT NULL, FK(comic_source_links.id) | Parent comic source link |
| chapter_source_link_id | TEXT | NULL, FK(chapter_source_links.id) | Optional chapter source link |
| source_page_id | TEXT | NOT NULL | Source-side page identifier |
| source_url | TEXT | NULL | Sanitized source URL |
| metadata_json | TEXT | NULL | Sanitized provenance payload |
| linked_at | TIMESTAMP | NOT NULL, DEFAULT CURRENT_TIMESTAMP | UTC |
| updated_at | TIMESTAMP | NOT NULL, DEFAULT CURRENT_TIMESTAMP | UTC |

**Indexes**:
- UNIQUE INDEX on `(comic_source_link_id, source_page_id)`
- INDEX on `page_id`
- Foreign key `(page_id) REFERENCES pages(id) ON DELETE CASCADE`
- Foreign key `(comic_source_link_id) REFERENCES comic_source_links(id) ON DELETE CASCADE`
- Foreign key `(chapter_source_link_id) REFERENCES chapter_source_links(id) ON DELETE SET NULL`

---

## Remote Detail Payload Mapping

Legacy source models expose rich remote detail payloads such as title, subtitle, cover, description, grouped chapters, tags, thumbnails, recommendations, favorite state, likes, comment counts, uploader, upload/update time, URL, stars, max-page hints, and comments.

Canonical DB must not store those payloads as a raw source runtime object.

They should be split by authority:

| Legacy detail field | Canonical direction | Authority note |
|---|---|---|
| `title` | `comic_metadata.title`, `comic_titles`, `comic_source_links.source_title` | User title and source title evidence are separate |
| `subTitle` | `comic_source_links.source_subtitle` | Source evidence only |
| `cover` | `comic_source_links.source_cover_url`, later storage object after download | URL evidence is not storage authority |
| `description` | `comic_metadata.description`, `comic_source_links.source_description` | User-facing metadata may diverge from source evidence |
| `tags: Map<String, List<String>>` | `source_tags`, `comic_source_link_tags`, `tag_mappings`, `canonical_tags` | Preserve namespace/value provenance before canonical mapping |
| `chapters` | `chapter_source_links` plus canonical `chapters` | Grouped/flat source chapters are provenance, not canonical chapter identity by themselves |
| `thumbnails` | future remote media evidence or source metadata JSON | Not page authority |
| `recommend` | future recommendation cache/provenance | Not canonical relationship authority in this schema |
| `isFavorite`, `favoriteId` | source/account provenance on `comic_source_links` | Must not replace local `favorites` authority |
| `isLiked`, `likesCount`, `commentCount`, `comments` | future remote social/comment evidence | Deferred; not V1 local metadata authority |
| `uploader` | `comic_source_links.source_uploader` | Source evidence only |
| `uploadTime` | `comic_source_links.source_upload_time` | Source evidence only |
| `updateTime` | `comic_source_links.source_update_time` | Source evidence only |
| `url` | `comic_source_links.source_url` | Sanitized source URL evidence |
| `stars` | `comic_source_links.source_stars` | Source rating evidence only |
| `maxPage` | `comic_source_links.source_max_page`, `comic_metadata.max_page_hint` | Hint only; actual pages remain canonical rows |
| `sourceKey`, `comicId`, `subId` | `source_platforms.canonical_key`, `comic_source_links.source_comic_id`, `comic_source_links.source_sub_id` | Provider identity must be canonicalized before storage |

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

## Table: operation_idempotency

Idempotency ledger for mutation workflows.

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| operation_name | TEXT | NOT NULL | e.g., `CreateCanonicalComic` |
| idempotency_key | TEXT | NOT NULL | Caller key (operation-scoped namespace) |
| input_hash | TEXT | NOT NULL | Canonical input hash |
| status | VARCHAR(20) | NOT NULL | `in_progress`, `completed`, or `failed` |
| result_type | TEXT | NULL | Result discriminator for replay |
| result_resource_id | TEXT | NULL | Primary resource identifier for replay |
| result_json | TEXT | NULL | Serialized replay payload |
| result_schema_version | TEXT | NULL | Replay payload schema version |
| created_at | TIMESTAMP | NOT NULL, DEFAULT CURRENT_TIMESTAMP | UTC |
| updated_at | TIMESTAMP | NOT NULL, DEFAULT CURRENT_TIMESTAMP | UTC |

**Indexes**:
- PRIMARY KEY `(operation_name, idempotency_key)`
- INDEX on `(operation_name, created_at)`

---

## Table: diagnostics_events

Persisted diagnostics evidence with explicit schema version.

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| id | TEXT | PRIMARY KEY | UUID v4 |
| schema_version | TEXT | NOT NULL | Diagnostics schema version (e.g., `1.0.0`) |
| timestamp | TIMESTAMP | NOT NULL | UTC |
| correlation_id | TEXT | NOT NULL | Trace ID |
| event_type | TEXT | NOT NULL | Namespaced type |
| category | TEXT | NOT NULL | Event category |
| severity | TEXT | NOT NULL | info/warning/error/critical |
| resource_type | TEXT | NULL | Optional |
| resource_id | TEXT | NULL | Optional |
| action | TEXT | NULL | Optional |
| payload | TEXT | NULL | Sanitized JSON payload |
| metadata | TEXT | NULL | Sanitized JSON metadata |
| duration | INTEGER | NULL | Milliseconds |
| success | BOOLEAN | NOT NULL | Result |
| error | TEXT | NULL | Sanitized JSON error envelope |

**Indexes**:
- PRIMARY KEY `id`
- INDEX on `timestamp`
- INDEX on `correlation_id`
- INDEX on `(event_type, timestamp)`
- INDEX on `(severity, timestamp)`
- INDEX on `resource_id`

---

## Table: favorites

User favorites.

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| id | UUID | PRIMARY KEY | Immutable |
| comic_id | UUID | NOT NULL, UNIQUE, FK(comics.id) | One per comic |
| marked_at | TIMESTAMP | NOT NULL, DEFAULT CURRENT_TIMESTAMP | Immutable |
| last_accessed_at | TIMESTAMP | NULL | Future read-activity policy field; not updated by current UpdateReaderPosition core use case |

**Indexes**:
- PRIMARY KEY `id`
- UNIQUE INDEX on `comic_id`
- INDEX on `marked_at`
- Foreign key `(comic_id) REFERENCES comics(id) ON DELETE CASCADE`

---

## Table: import_batches

Import batch metadata.

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| id | UUID | PRIMARY KEY | Immutable |
| source_type | VARCHAR(20) | NOT NULL | `cbz`, `pdf`, `directory` |
| source_ref | TEXT | NOT NULL | Adapter/import provenance reference only |
| files | TEXT | NOT NULL | JSON array of `ImportFile` |
| metadata | TEXT | NOT NULL | JSON import metadata |
| comic_id | UUID | NULL, FK(comics.id) | Assigned after completion |
| created_at | TIMESTAMP | NOT NULL, DEFAULT CURRENT_TIMESTAMP | UTC |
| completed_at | TIMESTAMP | NULL | Completion timestamp |

**Indexes**:
- PRIMARY KEY `id`
- INDEX on `(source_type, source_ref)`
- INDEX on `created_at`
- INDEX on `completed_at`
- Foreign key `(comic_id) REFERENCES comics(id) ON DELETE SET NULL`

**ImportFile Structure (JSON)**:
```json
{
  "path": "chapter1/page01.jpg",
  "fileType": "image",
  "index": 0,
  "checksum": "sha256_hex_string",
  "sizeBytes": 1024000
}
```

---

## Transaction Semantics

### Atomic Operations

1. **Create Comic with Metadata**:
- Claim/replay idempotency inside the same transaction when idempotency key is provided
- On replay hit with same `input_hash`: return stored completed result
- On same `(operation_name, idempotency_key)` with different `input_hash`: return `IDEMPOTENCY_CONFLICT` (fail closed, no mutation)
- INSERT into `comics`
- INSERT into `comic_metadata`
- INSERT/UPSERT canonical primary title record
- Record completed idempotency result only after canonical writes succeed
- No implicit `reader_sessions` creation
- All writes succeed or all rollback

2. **Create Chapter with Pages**:
- INSERT into `chapters`
- INSERT into `pages`
- INSERT into `page_orders` and `page_order_items` (default source order)
- All writes succeed or all rollback

3. **Complete Import**:
- INSERT/UPDATE `import_batches` with `completed_at = CURRENT_TIMESTAMP`
- UPDATE canonical entities via adapter-provenance mapping rules
- All writes succeed or all rollback

4. **Update Reader Position**:
- UPDATE `reader_sessions`
- No favorite coupling in current core contract
- Write scope stays within reader session persistence boundary

### Concurrency

- Reader position is last-write-wins.
- Chapter/page creation is serialized per comic.
- Source-link mutation is serialized per affected source link scope.
- Import idempotency is adapter/provenance policy (`source_ref + source_type` pattern is acceptable).

---

## Legacy Guardrails (Non-Authority)

The following legacy patterns are not canonical DB authority and must not be promoted:
- `source_platform_aliases`
- `is_enabled`
- provider/display-name identity matching
- filesystem authority fields (`cover_local_path`, `local_path`, `local_root_path`, `imported_from_path`)
- `source_ref_json` as runtime identity
- loose `source_key` identity
- provider-specific special taxonomy tables as core authority

---

## Migration/Backup Scope

- Pre-stable schema can be reset without compatibility guarantees.
- Legacy data movement is deferred adapter/import boundary work, not canonical DB migration contract.
- Backup/recovery strategy is deployment/infra policy and out of scope here.
- This document does not promise transaction-log shipping or PITR.
