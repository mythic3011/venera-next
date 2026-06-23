# Database Schema Specification

**Logical relational schema constraints with current SQLite reference mapping for Venera canonical runtime.**

---

This canonical runtime schema is in pre-stable schema-definition stage. Define canonical schema directly, reset unsafe early choices when needed, and do not pay migration compatibility tax for non-stable internal data.

`normalized_title` is a matching/search signal only. It is non-unique and must never be treated as canonical comic identity authority.

This schema document is portable only at the logical domain and constraint layer, not as raw physical DDL tokens. Unless a section says otherwise, the `Type` column below records the corrected pre-stable SQLite reference target. Runtime implementation may lag during schema-repair slices and must catch up before behavior is claimed complete.

Current logical type expectations that any future backend must map explicitly:

| Logical domain | Current SQLite reference | Notes |
|---|---|---|
| `Uuid` | `TEXT` | Immutable UUID string today; future backends may use native UUID storage |
| `Timestamp` | `TEXT` | UTC ISO string today; future backends may use native timestamp-with-time-zone storage |
| `DecimalString` | `TEXT` | Normalized decimal string for numeric ordering hints; compare with decimal/numeric semantics, not binary floating-point |
| `BooleanFlag` | `INTEGER CHECK (0, 1)` | Logical boolean today; integer storage is not the canonical cross-backend requirement |
| `JsonDocument` | `TEXT` | Canonical JSON payload today; future backends may use native JSON storage |

The current `runtime/core/src/db/database.ts` SQLite path remains valid for local, dev, embedded, test, and temporary demo modes. This schema document does not commit Venera to a future server-backed backend, portability timeline, or adapter roadmap. The current `apps/web` shell remains `demo-memory` only and intentionally non-persistent. If deployment-direction guidance is maintained separately, see `docs/design/archive/v1/production-database-adapter-strategy.md`.

## Table: comics

Canonical identity for comic works.

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| id | TEXT | PRIMARY KEY | Immutable UUID string |
| normalized_title | TEXT | NOT NULL | Lowercase normalized matching key (non-unique) |
| origin_hint | TEXT | NOT NULL, DEFAULT 'unknown', CHECK (origin_hint IN ('unknown', 'local', 'remote', 'mixed')) | Broad provenance hint for this comic work |
| library_status | TEXT | NOT NULL, DEFAULT 'active', CHECK (library_status IN ('active', 'removed')) | Library visibility/removal lifecycle |
| removed_at | TEXT | NULL | UTC ISO removal timestamp; NULL when active |
| created_at | TEXT | NOT NULL | UTC ISO string |
| updated_at | TEXT | NOT NULL | UTC ISO string |

**Indexes**:
- PRIMARY KEY `id`
- NON-UNIQUE INDEX on `normalized_title`
- INDEX on `library_status`
- CHECK `library_status IN ('active', 'removed')`

**Notes**:
- `origin_hint` is derived from active local/remote content-bearing source links and must be updated in the same application transaction that changes source-link membership or status.
- `virtual` source platforms do not contribute to `origin_hint`.
- `library_status = 'removed'` hides the comic from default library/browse surfaces while retaining child records and reader progress. Hard deletion is a separate purge flow.

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

### Source Platform Kind Semantics

- `local`: content comes from local/imported storage.
- `remote`: content comes from a network/provider integration.
- `virtual`: internal synthesized/projection platform only. It must not own storage credentials, fetch remote content, or model user-defined collections.

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
| config_schema_version | INTEGER | NOT NULL | Parser/validator version for `config_json` |
| secret_ref | TEXT | NULL | Optional reference to secrets store entry |
| status | TEXT | NOT NULL, CHECK (status IN ('active', 'disabled', 'deprecated')) | Backend lifecycle status |
| created_at | TEXT | NOT NULL | UTC ISO string |
| updated_at | TEXT | NOT NULL | UTC ISO string |

**Indexes**:
- PRIMARY KEY `id`
- UNIQUE INDEX on `backend_key`
- CHECK `backend_kind IN ('local_app_data', 'webdav', 'future')`
- CHECK `status IN ('active', 'disabled', 'deprecated')`

**Notes**:
- `config_schema_version` must be a supported positive integer. Unsupported versions fail closed before a backend is used.
- `config_json` must not contain plaintext secrets.
- `secret_ref` points to an external credential store entry (Keychain, Keystore, or deployment secret manager), not raw credential material.

---

## Table: storage_objects

Storage object metadata. Represents a logical object (file) independent of where it is physically stored.

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| id | TEXT | PRIMARY KEY | Immutable UUID string |
| object_kind | TEXT | NOT NULL, CHECK (object_kind IN ('page_image', 'cover', 'archive', 'backup', 'cache')) | What kind of object this is |
| content_hash | TEXT | NULL | Optional content-derived evidence for deduplication/verification; not primary identity authority in the current schema |
| size_bytes | INTEGER | NULL | Optional object size in bytes; may be absent before materialization/verification |
| mime_type | TEXT | NULL | Optional MIME type; may be absent before materialization/verification |
| created_at | TEXT | NOT NULL | UTC ISO string |
| updated_at | TEXT | NOT NULL | UTC ISO string |

**Indexes**:
- PRIMARY KEY `id`
- CHECK `object_kind IN ('page_image', 'cover', 'archive', 'backup', 'cache')`

**Notes**:
- Current object identity is the row `id`, not a hash-addressed key.
- `content_hash` is optional evidence in the current schema. If a future slice requires content-addressable authority, that slice must either make the hash mandatory for relevant object kinds or define a stricter split contract.
- A storage object with no placement whose `sync_status` has readable bytes is unavailable. Page/image loaders must surface `STORAGE_OBJECT_UNAVAILABLE` or an explicit placeholder/retry state, not treat row existence as byte availability.
- Authoritative synced placements should backfill `size_bytes` and `mime_type`; NULL is not a claim that long-term server-backed storage can ignore those fields indefinitely.

---

## Table: chapters

Ordered chapter sequence inside a comic. Supports nesting via `parent_chapter_id` for season/volume groupings.

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| id | TEXT | PRIMARY KEY | Immutable UUID string |
| comic_id | TEXT | NOT NULL, FK(comics.id) ON DELETE CASCADE | Parent comic; immutable |
| parent_chapter_id | TEXT | NULL, FK(chapters.id) ON DELETE NO ACTION DEFERRABLE | Optional parent chapter for nested groupings |
| chapter_kind | TEXT | NOT NULL, CHECK (chapter_kind IN ('season', 'volume', 'chapter', 'episode', 'oneshot', 'group')) | Structural kind of this chapter node |
| chapter_number | TEXT | NULL | Optional normalized decimal ordering hint (`1`, `1.5`, `2`). Non-unique, non-identity. |
| title | TEXT | NULL | Optional chapter name |
| display_label | TEXT | NULL | Optional display label; may differ from title |
| created_at | TEXT | NOT NULL | UTC ISO string |
| updated_at | TEXT | NOT NULL | UTC ISO string |

**Indexes**:
- PRIMARY KEY `id`
- INDEX on `comic_id`
- INDEX on `parent_chapter_id`
- Foreign key `(comic_id) REFERENCES comics(id) ON DELETE CASCADE`
- Foreign key `(parent_chapter_id) REFERENCES chapters(id) ON DELETE NO ACTION DEFERRABLE INITIALLY DEFERRED`
- CHECK `chapter_kind IN ('season', 'volume', 'chapter', 'episode', 'oneshot', 'group')`

**Notes**:
- `chapter_number` is nullable, non-unique, and never treated as an identity field. Multiple chapters may share the same `chapter_number` (e.g. split releases or decimal chapters).
- `chapter_number` is stored as a normalized decimal string to avoid binary floating-point comparison drift. Query paths must compare it with decimal/numeric semantics, not lexicographic text ordering.
- `parent_chapter_id` enables season/volume grouping without a separate grouping table.
- Parent deletion must not silently promote children to root-level chapters. Direct parent deletion must either delete the subtree, explicitly reparent children, or fail closed.
- The self-foreign-key does not prevent self-parenting or cycles by itself. Current mutation paths must reject self-parenting, reject parent/child cycles fail-closed, and reject nesting deeper than 8 nodes.
- Container-style `chapter_kind` values (`season`, `volume`, `group`) may own child chapters and normally should not own readable Pages directly; page-bearing imported/readable units should use `chapter`, `episode`, or `oneshot`.
- The allowed parent/child `chapter_kind` matrix is enforced in application/domain logic in the current schema, not DB constraints. Server-backed multi-writer approval requires an explicit portable nesting rule set before portable hierarchy claims are made.

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

**Notes**:
- Current lifecycle is update-in-place across `active`, `candidate`, `rejected`, and `stale`. A rejected or stale row does not automatically free `(source_platform_id, remote_work_id)` for a second row in the same schema.
- If future product scope needs append-only provenance history or recreate-after-reject semantics, this uniqueness model must change before that behavior is approved.

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
| confidence | TEXT | NOT NULL, CHECK (confidence IN ('manual', 'auto_high', 'auto_low')) | Confidence level of this chapter mapping |
| created_at | TEXT | NOT NULL | UTC ISO string |
| updated_at | TEXT | NOT NULL | UTC ISO string |

**Indexes**:
- PRIMARY KEY `id`
- UNIQUE INDEX on `(source_link_id, remote_chapter_id)`
- INDEX on `chapter_id`
- Foreign key `(chapter_id) REFERENCES chapters(id) ON DELETE CASCADE`
- Foreign key `(source_link_id) REFERENCES source_links(id) ON DELETE CASCADE`
- CHECK `link_status IN ('active', 'inactive', 'stale')`
- CHECK `confidence IN ('manual', 'auto_high', 'auto_low')`

**Source order aggregation**: The canonical display order for a chapter derived from source is `MIN(source_order)` across active chapter source links with non-null `source_order`. Active chapter source links are those with `chapter_source_links.link_status = 'active'`, parent `source_links.link_status = 'active'`, and parent `source_platforms.status = 'active'`. If no active links with a non-null `source_order` exist, source order is absent.

---

## Table: pages

Ordered pages inside a chapter.

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| id | TEXT | PRIMARY KEY | Immutable UUID string |
| chapter_id | TEXT | NOT NULL, FK(chapters.id) ON DELETE CASCADE | Parent chapter; immutable |
| page_index | INTEGER | NOT NULL | 0-based source/insertion index; gaps are allowed |
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
- UNIQUE INDEX on `(chapter_id, page_index)` — enforces non-duplicate page positions within a chapter; it does not require contiguity
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
| cover_status | TEXT | NOT NULL, DEFAULT 'none', CHECK (cover_status IN ('none', 'pending', 'local_only', 'synced')) | Cover lifecycle authority |
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
- CHECK `cover_status IN ('none', 'pending', 'local_only', 'synced')`

**Invariant**: `comic_metadata.title` must always equal the `title` of the `comic_titles` row for this comic where `title_kind = 'primary'`. Any mutation that changes the primary title must update both records atomically.

This duplicated title field is a current local-read optimization, not an approved multi-writer/server-backed truth model. Any future server-backed backend must either add DB-backed consistency enforcement or drop the duplicated cache in favor of deriving the user-facing title from `comic_titles`.

**Cover lifecycle rules**:
- `cover_status = 'none'`: `cover_page_id` and `cover_storage_object_id` must both be NULL.
- `cover_status = 'pending'`: cover resolution/materialization is in progress; cover references may still be NULL.
- `cover_status = 'local_only'`: at least one of `cover_page_id` or `cover_storage_object_id` must be present.
- `cover_status = 'synced'`: `cover_storage_object_id` must be present and should point to a storage object with a synced authoritative placement.
- If both cover references are present, `cover_page_id` must reference a Page whose `storage_object_id` equals `cover_storage_object_id`; mismatches are invalid.
- Effective cover resolution uses `cover_storage_object_id` directly when present, otherwise derives from `cover_page_id.storage_object_id` when available.
- These lifecycle rules are enforced in application/domain logic in the current schema. A server-backed multi-writer backend must add DB constraints/triggers or a stricter table split before claiming portable enforcement.

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
- LOGICAL UNIQUE constraint on `(comic_id, normalized_title, locale, source_platform_id)` with NULL locale/source-platform buckets treated as not distinct — prevents duplicate title evidence per locale/platform combination
- PARTIAL UNIQUE INDEX on `(comic_id)` WHERE `title_kind = 'primary'` — enforces exactly one primary title per comic
- Foreign key `(comic_id) REFERENCES comics(id) ON DELETE CASCADE`
- Foreign key `(source_platform_id) REFERENCES source_platforms(id) ON DELETE SET NULL`
- Foreign key `(source_link_id) REFERENCES source_links(id) ON DELETE SET NULL`
- CHECK `title_kind IN ('primary', 'source', 'alias')`

**Notes**:
- `title_kind` values: `primary` (the user-facing canonical title), `source` (evidence from a source platform), `alias` (alternate known title).
- The partial unique index enforces at most one `primary` title per comic. It does not enforce at least one primary row by itself.
- Create/update/delete title use cases must enforce the minimum-one-primary invariant in the same transaction that maintains `comic_metadata.title`.
- A future server-backed multi-writer backend must add a trigger/constraint strategy or replace the cache with a `primary_title_id`-style authority before claiming DB-level minimum-one-primary enforcement.
- The logical uniqueness rule treats missing `locale` and missing `source_platform_id` as value-bearing buckets, not "duplicates allowed because NULL is special". Backend-specific enforcement must preserve that rule explicitly.

---

## Table: page_orders

Named page-order profiles for a chapter. One active order per chapter is enforced by a partial unique index.

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| id | TEXT | PRIMARY KEY | UUID v4 string |
| chapter_id | TEXT | NOT NULL, FK(chapters.id) ON DELETE CASCADE | Parent chapter |
| order_type | TEXT | NOT NULL, CHECK (order_type IN ('source', 'user_override', 'import_detected', 'custom')) | Single semantic order discriminator |
| status | TEXT | NOT NULL, CHECK (status IN ('active', 'inactive', 'superseded', 'archived')) | Order profile lifecycle state |
| created_at | TEXT | NOT NULL | UTC ISO string |
| updated_at | TEXT | NOT NULL | UTC ISO string |

**Indexes**:
- PRIMARY KEY `id`
- INDEX on `chapter_id`
- PARTIAL UNIQUE INDEX on `(chapter_id)` WHERE `status = 'active'` — enforces at most one active order per chapter
- Foreign key `(chapter_id) REFERENCES chapters(id) ON DELETE CASCADE`
- CHECK `order_type IN ('source', 'user_override', 'import_detected', 'custom')`
- CHECK `status IN ('active', 'inactive', 'superseded', 'archived')`

**Notes**:
- `order_type` is the only order discriminator. The former split between `order_key = 'user'` and `order_type = 'user_override'` represented one concept twice and is not part of the canonical design.
- `status` is lifecycle state, not a boolean. `active` is the profile currently used for reading, `inactive` is retained but not current, `superseded` was replaced by a newer profile, and `archived` is deliberately retained historical state.
- Page counts are derived from `page_order_items` and chapter pages. `page_orders` must not store a separate `page_count` cache.
- Source order may exist as a synthetic/runtime-derived order even when no persisted `page_orders` row with `order_type = 'source'` exists.

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
- PARTIAL UNIQUE INDEX on `(storage_object_id)` WHERE `role = 'authority'` — at most one authority placement per storage object
- Foreign key `(storage_object_id) REFERENCES storage_objects(id) ON DELETE CASCADE`
- Foreign key `(storage_backend_id) REFERENCES storage_backends(id) ON DELETE RESTRICT`
- CHECK `role IN ('authority', 'cache', 'mirror', 'staging')`
- CHECK `sync_status IN ('pending', 'uploading', 'synced', 'failed', 'evicted')`

**Notes**:
- Cache, mirror, and staging placements may coexist for the same storage object.
- Authority placement is singular. Any implementation that allows multiple `role = 'authority'` rows for one object is out of contract with this schema authority.

---

## Table: reader_sessions

Canonical reader position lifecycle rows. A comic may have historical/suspended/abandoned rows, but only one active resume candidate.

The saved reader position authority is `page_id`. Chapter and page-index position are derived by joining the referenced `pages` row.

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| id | TEXT | PRIMARY KEY | Immutable UUID string |
| comic_id | TEXT | NOT NULL, FK(comics.id) ON DELETE CASCADE | Parent comic |
| page_id | TEXT | NOT NULL, FK(pages.id) ON DELETE NO ACTION DEFERRABLE | Current page identity; position authority |
| source_link_id | TEXT | NULL, FK(source_links.id) ON DELETE SET NULL | Optional last read-source context for source preference/fallback |
| session_state | TEXT | NOT NULL, CHECK (session_state IN ('active', 'suspended', 'completed', 'abandoned')) | Reader session lifecycle state |
| created_at | TEXT | NOT NULL | UTC ISO string |
| updated_at | TEXT | NOT NULL | UTC ISO string |

**Indexes**:
- PRIMARY KEY `id`
- INDEX on `comic_id`
- PARTIAL UNIQUE INDEX on `(comic_id)` WHERE `session_state = 'active'` — enforces at most one active session per comic
- INDEX on `source_link_id`
- Foreign key `(comic_id) REFERENCES comics(id) ON DELETE CASCADE`
- Foreign key `(page_id) REFERENCES pages(id) ON DELETE NO ACTION DEFERRABLE INITIALLY DEFERRED`
- Foreign key `(source_link_id) REFERENCES source_links(id) ON DELETE SET NULL`
- CHECK `session_state IN ('active', 'suspended', 'completed', 'abandoned')`

**Position authority rules**:
- The authoritative saved position is `page_id`.
- `chapter_id` and `page_index` are derived from the referenced `pages` row and must not be duplicated on `reader_sessions`.
- The referenced Page's Chapter must belong to `reader_sessions.comic_id`; current enforcement is application/domain-level because this is a cross-table ownership invariant.
- The `page_id` foreign key must not use immediate `RESTRICT`; permanent Comic deletion must not depend on undefined cascade ordering between `reader_sessions` and `chapters -> pages`.
- Direct Page deletion while ReaderSession rows still reference that Page must fail unless the same transaction first abandons/deletes or rewrites those sessions.
- `source_link_id`, when present, is read-context evidence only. It must belong to the same comic and may point to a stale link for historical context, but resolver fallback must prefer active alternatives when available.
- `session_state` is lifecycle state, not a boolean. Only `active` sessions are resume candidates.
- Multiple non-active lifecycle rows may exist for the same comic; they are historical evidence unless a future resume-history policy promotes them.
- Current reader session persistence is single-user, single-runtime convenience state. It is not an approved multi-device sync contract.
- Position updates are last-write-wins and carry no version/conflict signal. Any future multi-device or server-backed mode must add an explicit conflict-resolution contract before approval.

---

## Table: user_collections

User-defined grouping of comics across platforms/sources.

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| id | TEXT | PRIMARY KEY | Immutable UUID string |
| display_name | TEXT | NOT NULL | User-facing collection name |
| description | TEXT | NULL | Optional collection description |
| cover_storage_object_id | TEXT | NULL, FK(storage_objects.id) ON DELETE SET NULL | Optional collection cover object |
| sort_order | TEXT | NOT NULL, DEFAULT 'manual', CHECK (sort_order IN ('manual', 'title', 'updated_at', 'last_read')) | Collection display ordering policy |
| created_at | TEXT | NOT NULL | UTC ISO string |
| updated_at | TEXT | NOT NULL | UTC ISO string |

**Indexes**:
- PRIMARY KEY `id`
- Foreign key `(cover_storage_object_id) REFERENCES storage_objects(id) ON DELETE SET NULL`
- CHECK `sort_order IN ('manual', 'title', 'updated_at', 'last_read')`

**Notes**:
- Collections are user-owned grouping surfaces, not source identity or provenance.
- Collection cover display must still verify readable storage placement before claiming the cover bytes are available.

---

## Table: user_collection_items

Membership and manual ordering for comics inside user collections.

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| id | TEXT | PRIMARY KEY | Immutable UUID string |
| collection_id | TEXT | NOT NULL, FK(user_collections.id) ON DELETE CASCADE | Parent collection |
| comic_id | TEXT | NOT NULL, FK(comics.id) ON DELETE CASCADE | Referenced comic |
| sort_index | INTEGER | NOT NULL | Explicit manual order position |
| pinned_at | TEXT | NULL | Optional pin timestamp |
| added_at | TEXT | NOT NULL | UTC ISO membership timestamp |

**Indexes**:
- PRIMARY KEY `id`
- UNIQUE INDEX on `(collection_id, comic_id)`
- UNIQUE INDEX on `(collection_id, sort_index)`
- INDEX on `comic_id`
- Foreign key `(collection_id) REFERENCES user_collections(id) ON DELETE CASCADE`
- Foreign key `(comic_id) REFERENCES comics(id) ON DELETE CASCADE`

**Notes**:
- `(collection_id, comic_id)` prevents duplicate membership.
- `sort_index` is manual-order authority when the parent collection has `sort_order = 'manual'`.
- A comic with `library_status = 'removed'` may remain in a collection until explicitly removed from that collection.

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

**Current contract**:
- `input_hash` is lowercase SHA-256 hex over canonical JSON for the operation input after operation-defined defaults and normalization; sorted object keys are required, and volatile runtime fields are excluded unless explicitly part of that operation's input contract.
- Same `(operation_name, idempotency_key)` with the same `input_hash` and status `completed` is replayable.
- Same `(operation_name, idempotency_key)` with a different `input_hash` returns `IDEMPOTENCY_CONFLICT`.
- Same `(operation_name, idempotency_key)` with status `in_progress` and a non-expired operation lease is not replayable. Current contract fails closed; it does not block or poll.
- Stale `in_progress` records are determined by `updated_at + operationLeaseTtl`. The default lease TTL is 5 minutes unless the operation explicitly defines a shorter TTL; long-running operations must renew `updated_at` before expiry.
- When an `in_progress` record is stale and the caller supplies the same `input_hash`, the use case may atomically reclaim the key by writing a fresh `in_progress` attempt before performing the mutation.
- Failed records are not replayable as success. The same input may retry after the operation retry TTL, default 5 minutes from `updated_at`; before that retry window opens, the use case fails closed.
- `status = 'completed'` requires replayable result evidence: `result_type` and either `result_resource_id` or `result_json`.
- `result_schema_version` is required when `result_json` is present.
- Completed records are terminal in the current contract; failed records are not replayable.

**Cleanup policy**:
- Periodic cleanup may purge stale `failed` records and stale unclaimed `in_progress` records after the operation retention window.
- Cleanup must not remove `completed` records before their replay retention window expires.

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

**Notes**:
- Current canonical use is bounded diagnostics evidence for local/dev and short-lived runtime troubleshooting, not an approval to keep unbounded application logging in the main runtime DB forever.
- No server-backed retention, partitioning, or external-log-store policy is defined here. Any long-retention or high-volume production diagnostics scope requires a dedicated storage/retention authority first.

---

## Removed Tables (Not in Current Core Pass)

The following tables are **not present** in the current canonical schema pass and must not be referenced as current authority:

- **`page_source_links`** — page-level source links are deferred. No `page_source_links` table exists in the current schema.
- **`favorites`** — no favorites table in the current core pass. Source account favorite state is evidence on `source_links`; local favorite authority is deferred.
- **`import_batches`** — no import batch tracking table in the current core pass. `ImportBatch` is a Deferred/Legacy entity reference for import-adapter workflows only.

---

## Remote Detail Payload Mapping

Legacy source models expose rich remote detail payloads such as title, subtitle, cover, description, grouped chapters, tags, thumbnails, recommendations, favorite state, likes, comment counts, uploader, upload/update time, URL, stars, max-page hints, and comments.

Canonical DB must not store those payloads as a raw source runtime object.

They should be split by authority:

| Legacy detail field | Canonical direction | Authority note |
|---|---|---|
| `title` | `comic_metadata.title`, `comic_titles`, `source_links.display_title` | User title and source title evidence are separate |
| `subTitle` | `source_links.display_title` (evidence) | Source evidence only |
| `cover` | `comic_metadata.cover_status`, `comic_metadata.cover_page_id`, `comic_metadata.cover_storage_object_id`, storage pipeline | Cover lifecycle, local page reference, and storage authority are separate; URL evidence is not storage authority |
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

Future source package tables must preserve the trust/verification split:
- manifest/repository metadata may declare `trust_tier` and publisher key fingerprint
- package-store artifact metadata must persist install-time `verification_tier`, publisher key fingerprint, and signature evidence digest
- signature/authenticity verification must happen before durable package-store commit or source-platform mutation

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
   - Ensure the initial resolved page order is the canonical source sequence (`page_index` ascending), either through synthetic fallback or explicit `page_orders` materialization
   - All writes succeed or all rollback

3. **Update Reader Position**:
   - Resolve the requested position to a concrete `page_id`
   - INSERT or UPDATE the active `reader_sessions` row for the comic with `page_id`, optional `source_link_id`, and `session_state`
   - If a write creates a new active session while a previous active session exists, the previous active row must be transitioned to a non-active lifecycle state or the write must fail on the partial unique active-session constraint
   - No favorite coupling in current core contract
   - Write scope stays within reader session persistence boundary

4. **Permanently Delete Comic**:
   - Explicitly delete or cascade-delete `reader_sessions` for the Comic before deleting Chapters/Pages, or use deferred `NO ACTION` page-position constraints so the transaction is validated only after all cascades complete
   - DELETE the Comic and dependent rows in one transaction
   - Must not rely on undefined physical cascade ordering to satisfy `reader_sessions.page_id`

5. **Delete Chapter Node**:
   - Direct parent deletion must choose an explicit mode: delete subtree, reparent children, or reject when children exist
   - Must not rely on `ON DELETE SET NULL` to silently promote child chapters to root-level nodes

### Concurrency

- Reader position is last-write-wins within the current single-runtime local model.
- "Serialized per comic" and "serialized per affected source link scope" are application requirements, not a specified backend-portable locking mechanism.
- This schema does not currently define a backend-portable lock strategy such as app mutexes, `SELECT FOR UPDATE`, advisory locks, or SERIALIZABLE retry rules.
- Any server-backed backend must add an explicit locking and isolation contract before portable concurrency claims are made.

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
- `order_name` / `normalized_order_name` on page_orders (removed; `order_type` is the single order discriminator)
- `order_key` on page_orders (removed; duplicated `order_type`)
- `is_active` on page_orders (replaced by `status`)
- `page_count` on page_orders (removed; derived from `page_order_items`)
- `sort_order` on page_order_items (replaced by `sort_index`)
- `is_hidden` on page_order_items (removed)

---

## Migration/Backup Scope

- Pre-stable schema can be reset without compatibility guarantees.
- Legacy data movement is deferred adapter/import boundary work, not canonical DB migration contract.
- Backup/recovery strategy is deployment/infra policy and out of scope here.
- This document does not promise transaction-log shipping or PITR.
