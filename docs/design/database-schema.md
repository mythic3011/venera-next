# Database Schema Specification

**Language-agnostic relational schema for Venera canonical runtime.**

---

This canonical runtime schema is still in the pre-stable schema-definition stage. Define the canonical schema directly, reset unsafe early schema choices when needed, and do not pay migration compatibility tax for non-stable internal data.

## Table: comics

Canonical identity for comic works.

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| id | UUID | PRIMARY KEY | Immutable |
| normalized_title | TEXT | NOT NULL | Lowercase, no punctuation, for search and matching only |
| created_at | TIMESTAMP | NOT NULL, DEFAULT CURRENT_TIMESTAMP | UTC |
| updated_at | TIMESTAMP | NOT NULL, DEFAULT CURRENT_TIMESTAMP | UTC |

**Indexes**:
- PRIMARY KEY `id`
- NON-UNIQUE INDEX on `normalized_title`

---

## Table: comic_metadata

Mutable properties of comics.

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| comic_id | UUID | PRIMARY KEY, FK(comics.id) | Immutable |
| title | TEXT | NOT NULL | User-facing, may contain punctuation |
| description | TEXT | NULL | Optional long text |
| cover_local_path | TEXT | NULL | Optional file path to cached cover |
| author_name | TEXT | NULL | Optional |
| genre_tags | TEXT | NULL | JSON array of strings |

**Indexes**:
- PRIMARY KEY `comic_id`
- Foreign key `(comic_id) REFERENCES comics(id) ON DELETE CASCADE`

---

## Table: chapters

Ordered sequences of pages.

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| id | UUID | PRIMARY KEY | Immutable |
| comic_id | UUID | NOT NULL, FK(comics.id) | Immutable |
| chapter_number | FLOAT | NOT NULL | Canonical order (e.g., 1.0, 1.5, 2.0) |
| title | TEXT | NULL | Optional chapter name |
| source_platform_id | UUID | NULL, FK(source_platforms.id) | Optional link |
| source_chapter_id | TEXT | NULL | Optional source-specific ID |
| created_at | TIMESTAMP | NOT NULL, DEFAULT CURRENT_TIMESTAMP | UTC |
| updated_at | TIMESTAMP | NOT NULL, DEFAULT CURRENT_TIMESTAMP | UTC |

**Indexes**:
- PRIMARY KEY `id`
- UNIQUE INDEX on `(comic_id, chapter_number)`
- Foreign key `(comic_id) REFERENCES comics(id) ON DELETE CASCADE`
- Foreign key `(source_platform_id) REFERENCES source_platforms(id) ON DELETE SET NULL`

---

## Table: pages

Ordered images within chapters.

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| id | UUID | PRIMARY KEY | Immutable |
| chapter_id | UUID | NOT NULL, FK(chapters.id) | Immutable |
| page_index | INTEGER | NOT NULL | 0-based, contiguous within chapter |
| source_platform_id | UUID | NULL, FK(source_platforms.id) | Optional link |
| source_page_id | TEXT | NULL | Optional source-specific ID |
| local_cache_path | TEXT | NULL | Optional file path to cached image |
| created_at | TIMESTAMP | NOT NULL, DEFAULT CURRENT_TIMESTAMP | UTC |
| updated_at | TIMESTAMP | NOT NULL, DEFAULT CURRENT_TIMESTAMP | UTC |

**Indexes**:
- PRIMARY KEY `id`
- UNIQUE INDEX on `(chapter_id, page_index)`
- Foreign key `(chapter_id) REFERENCES chapters(id) ON DELETE CASCADE`
- Foreign key `(source_platform_id) REFERENCES source_platforms(id) ON DELETE SET NULL`

---

## Table: page_orders

Policy for page ordering (source vs. user override vs. import detected).

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| id | TEXT | PRIMARY KEY | UUID v4 string |
| chapter_id | UUID | NOT NULL, UNIQUE, FK(chapters.id) | One per chapter |
| page_count | INTEGER | NOT NULL | Informational (for audit trail) |
| order_type | VARCHAR(20) | NOT NULL | 'source', 'user_override', 'import_detected' |
| user_pages_order | TEXT | NULL | Comma-delimited page IDs if override |
| created_at | TIMESTAMP | NOT NULL, DEFAULT CURRENT_TIMESTAMP | UTC |
| updated_at | TIMESTAMP | NOT NULL, DEFAULT CURRENT_TIMESTAMP | UTC |

**Indexes**:
- PRIMARY KEY `id`
- UNIQUE INDEX on `chapter_id`
- Foreign key `(chapter_id) REFERENCES chapters(id) ON DELETE CASCADE`
- CHECK `order_type IN ('source', 'user_override', 'import_detected')`

---

## Table: reader_sessions

Normalized reader position state.

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| id | UUID | PRIMARY KEY | Immutable |
| comic_id | UUID | NOT NULL, UNIQUE, FK(comics.id) | One per comic |
| chapter_id | UUID | NOT NULL, FK(chapters.id) | Current chapter |
| page_index | INTEGER | NOT NULL | 0-based position |
| active_tab_position | INTEGER | NOT NULL, DEFAULT 0 | Reserved for future multi-tab |
| created_at | TIMESTAMP | NOT NULL, DEFAULT CURRENT_TIMESTAMP | UTC |
| updated_at | TIMESTAMP | NOT NULL, DEFAULT CURRENT_TIMESTAMP | UTC |

**Indexes**:
- PRIMARY KEY `id`
- UNIQUE INDEX on `comic_id`
- Foreign key `(comic_id) REFERENCES comics(id) ON DELETE CASCADE`
- Foreign key `(chapter_id) REFERENCES chapters(id) ON DELETE RESTRICT`

---

## Table: source_platforms

Providers of comics (local, remote, virtual).

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| id | UUID | PRIMARY KEY | Immutable |
| canonical_key | TEXT | NOT NULL, UNIQUE | Stable identifier (e.g., "copymanga", "local") |
| display_name | TEXT | NOT NULL | User-facing name |
| kind | VARCHAR(20) | NOT NULL | 'local', 'remote', 'virtual' |
| is_enabled | BOOLEAN | NOT NULL, DEFAULT TRUE | Active source flag |
| created_at | TIMESTAMP | NOT NULL, DEFAULT CURRENT_TIMESTAMP | UTC |
| updated_at | TIMESTAMP | NOT NULL, DEFAULT CURRENT_TIMESTAMP | UTC |

**Indexes**:
- PRIMARY KEY `id`
- UNIQUE INDEX on `canonical_key`
- CHECK `kind IN ('local', 'remote', 'virtual')`

---

## Table: source_manifests

Provider-specific behavior manifests (loaded from JSON, validated).

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| id | TEXT | PRIMARY KEY | Deterministic hash of content |
| source_platform_id | UUID | NOT NULL, FK(source_platforms.id) | Parent platform |
| version | TEXT | NOT NULL | Semver (e.g., "1.0.0") |
| provider | TEXT | NOT NULL | Name matching source platform |
| display_name | TEXT | NOT NULL | User-facing name |
| base_url | TEXT | NOT NULL | Endpoint base URL |
| headers | TEXT | NOT NULL | JSON object of static headers (no secrets) |
| search | TEXT | NOT NULL | JSON object for search endpoint config |
| comic_detail | TEXT | NOT NULL | JSON object for comic detail config |
| chapter_list | TEXT | NOT NULL | JSON object for chapter listing config |
| page_list | TEXT | NOT NULL | JSON object for page listing config |
| image_url | TEXT | NOT NULL | JSON object for image URL transformation rules |
| permissions | TEXT | NOT NULL | JSON array of required permissions |
| runtime_version | TEXT | NULL | Minimum required runtime version |
| created_at | TIMESTAMP | NOT NULL, DEFAULT CURRENT_TIMESTAMP | UTC |

**Indexes**:
- PRIMARY KEY `id`
- Foreign key `(source_platform_id) REFERENCES source_platforms(id) ON DELETE CASCADE`

**Validation**:
- All JSON columns must be valid JSON
- Must validate against `schemas/source_manifest.schema.json`
- No secrets in `headers` column

---

## Table: favorites

User's marked works.

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| id | UUID | PRIMARY KEY | Immutable |
| comic_id | UUID | NOT NULL, UNIQUE, FK(comics.id) | One per comic |
| marked_at | TIMESTAMP | NOT NULL, DEFAULT CURRENT_TIMESTAMP | Immutable |
| last_accessed_at | TIMESTAMP | NULL | Updated on reader access |

**Indexes**:
- PRIMARY KEY `id`
- UNIQUE INDEX on `comic_id`
- Foreign key `(comic_id) REFERENCES comics(id) ON DELETE CASCADE`

---

## Table: import_batches

Metadata for file imports (CBZ, PDF, directories).

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| id | UUID | PRIMARY KEY | Immutable |
| source_type | VARCHAR(20) | NOT NULL | 'cbz', 'pdf', 'directory' |
| source_path | TEXT | NOT NULL | Path to import source |
| files | TEXT | NOT NULL | JSON array of ImportFile objects |
| metadata | TEXT | NOT NULL | JSON object of import-specific metadata |
| comic_id | UUID | NULL, FK(comics.id) | Assigned after import completes |
| created_at | TIMESTAMP | NOT NULL, DEFAULT CURRENT_TIMESTAMP | UTC |
| completed_at | TIMESTAMP | NULL | Set when import completes |

**Indexes**:
- PRIMARY KEY `id`
- Foreign key `(comic_id) REFERENCES comics(id) ON DELETE SET NULL`
- CHECK `source_type IN ('cbz', 'pdf', 'directory')`

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
   - INSERT into `comics`
   - INSERT into `comic_metadata`
   - INSERT into `reader_sessions` (default position)
   - All three succeed or all rollback

2. **Create Chapter with Pages**:
   - INSERT into `chapters`
   - INSERT into `pages` (all pages in batch)
   - INSERT into `page_orders` (default source order)
   - All succeed or all rollback

3. **Complete Import**:
   - INSERT into `import_batches` with `completed_at = NOW()`
   - UPDATE `comic_metadata` (from import manifest)
   - UPDATE `chapters` and `pages` with source links
   - All succeed or all rollback

4. **Update Reader Position**:
   - UPDATE `reader_sessions` with new chapter/page
   - UPDATE `favorites.last_accessed_at` if favorited
   - Both succeed or both rollback

### Concurrency

- Reader position updates are **last-write-wins** (no locking required)
- Chapter/page creation is **serialized** (mutex per comic)
- Source platform changes require **exclusive lock**
- ImportBatch creation is **idempotent** (check by `source_path + source_type`)

---

## Cascade Behavior

| Foreign Key | Delete Action | Update Action | Notes |
|---|---|---|---|
| `comic_id` → `comics` | CASCADE | RESTRICT | Deleting comic deletes all related data |
| `chapter_id` → `chapters` | CASCADE | RESTRICT | Deleting chapter deletes pages |
| `source_platform_id` → `source_platforms` | SET NULL | RESTRICT | Removing platform orphans but doesn't delete source data |
| `comic_id` → `import_batches` | SET NULL | RESTRICT | Completing import links batch, but batch survives if comic deleted |

---

## Data Types Reference

| Type | Mapping | Notes |
|------|---------|-------|
| UUID | UUID (native) or TEXT | Native UUID if DB supports, else 36-char string |
| TEXT | VARCHAR or TEXT | Unbounded string |
| INTEGER | INT or BIGINT | Whole numbers |
| FLOAT | REAL or DOUBLE | Decimal numbers (chapter ordering) |
| TIMESTAMP | DATETIME or TIMESTAMP | UTC, with timezone |
| BOOLEAN | BOOLEAN or TINYINT(1) | True/false values |
| JSON | JSON or TEXT | JSON text, validated on read |

---

## Naming Conventions

- **Table names**: `snake_case`, pluralized (e.g., `chapters`)
- **Column names**: `snake_case` (e.g., `page_index`)
- **Foreign keys**: `{table_name}_id` (e.g., `comic_id`)
- **Indexes**: Descriptive names (e.g., `ix_chapters_comic_number`)
- **Constraints**: Prefixed (e.g., `ck_chapters_number_positive`)

---

## Migration Path from Legacy

**Phased approach**:

1. **Phase 1**: Create new canonical schema alongside legacy `comics` table
2. **Phase 2**: Hydrate new tables from legacy data
3. **Phase 3**: Create triggers to keep old schema in sync (read-only views)
4. **Phase 4**: Switch application to new schema, legacy as read-only reference
5. **Phase 5**: Archive legacy tables (no deletion until stable)

---

## Backup & Recovery

- **Full backup**: All tables with data
- **Incremental**: Changes since last checkpoint
- **Point-in-time recovery**: Supported via transaction log
- **Audit trail**: `created_at`, `updated_at` timestamps on all records
- **Checksums**: `import_batches.files[].checksum` for integrity verification
