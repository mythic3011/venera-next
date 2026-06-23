# Venera Database Schema
> Pre-stable. Logical schema with SQLite reference mapping.
> Type column = corrected SQLite target. Future backends must map explicitly.

## Type Mapping

| Logical | SQLite | Notes |
|---|---|---|
| Uuid | TEXT | RFC 4122 string |
| Timestamp | TEXT | UTC ISO 8601 |
| DecimalString | TEXT | Decimal comparison, never lexicographic |
| Boolean | INTEGER CHECK(0,1) | |
| JsonDocument | TEXT | Canonical JSON |
| Float32Array | BLOB | For vector storage |

---

## contents (replaces comics)

```sql
CREATE TABLE contents (
  id            TEXT PRIMARY KEY,
  content_type  TEXT NOT NULL CHECK (content_type IN ('comic','webtoon','illustrated','novel','article','document','note')),
  normalized_title TEXT NOT NULL,
  origin_hint   TEXT NOT NULL DEFAULT 'unknown' CHECK (origin_hint IN ('unknown','local','remote','mixed')),
  library_status TEXT NOT NULL DEFAULT 'active' CHECK (library_status IN ('active','removed')),
  removed_at    TEXT,
  created_at    TEXT NOT NULL,
  updated_at    TEXT NOT NULL
);
CREATE INDEX idx_contents_normalized_title ON contents(normalized_title);
CREATE INDEX idx_contents_library_status   ON contents(library_status);
CREATE INDEX idx_contents_content_type     ON contents(content_type);
```

## content_metadata

```sql
CREATE TABLE content_metadata (
  content_id              TEXT PRIMARY KEY REFERENCES contents(id) ON DELETE CASCADE,
  title                   TEXT NOT NULL,
  description             TEXT,
  cover_status            TEXT NOT NULL DEFAULT 'none' CHECK (cover_status IN ('none','pending','local_only','synced')),
  cover_unit_id           TEXT REFERENCES content_units(id) ON DELETE SET NULL,
  cover_storage_object_id TEXT REFERENCES storage_objects(id) ON DELETE SET NULL,
  author_name             TEXT,
  metadata_json           TEXT,
  created_at              TEXT NOT NULL,
  updated_at              TEXT NOT NULL
);
-- cover conflict rule: if both refs present, cover_unit_id.storage_object_id must equal cover_storage_object_id
-- enforced at application layer
```

## content_titles

```sql
CREATE TABLE content_titles (
  id                TEXT PRIMARY KEY,
  content_id        TEXT NOT NULL REFERENCES contents(id) ON DELETE CASCADE,
  title             TEXT NOT NULL,
  normalized_title  TEXT NOT NULL,
  locale            TEXT,
  source_platform_id TEXT REFERENCES source_platforms(id) ON DELETE SET NULL,
  source_link_id    TEXT REFERENCES source_links(id) ON DELETE SET NULL,
  title_kind        TEXT NOT NULL CHECK (title_kind IN ('primary','source','alias')),
  created_at        TEXT NOT NULL
);
CREATE INDEX idx_content_titles_content_id     ON content_titles(content_id);
CREATE INDEX idx_content_titles_normalized     ON content_titles(normalized_title);
CREATE INDEX idx_content_titles_kind           ON content_titles(content_id, title_kind);
-- Exactly one primary per content
CREATE UNIQUE INDEX ux_content_titles_one_primary
  ON content_titles(content_id) WHERE title_kind = 'primary';
```

## content_sections (replaces chapters)

```sql
CREATE TABLE content_sections (
  id                TEXT PRIMARY KEY,
  content_id        TEXT NOT NULL REFERENCES contents(id) ON DELETE CASCADE,
  parent_section_id TEXT REFERENCES content_sections(id) ON DELETE SET NULL,
  section_kind      TEXT NOT NULL CHECK (section_kind IN ('season','volume','chapter','episode','oneshot','group','section','entry','article','part')),
  section_number    TEXT,   -- DecimalString, nullable, non-unique, ordering hint only
  title             TEXT,
  display_label     TEXT,
  created_at        TEXT NOT NULL,
  updated_at        TEXT NOT NULL
);
CREATE INDEX idx_sections_content_id      ON content_sections(content_id);
CREATE INDEX idx_sections_parent          ON content_sections(parent_section_id);
-- section_number compared with CAST(section_number AS REAL) — never lexicographic
-- cycle/self-parent/depth enforcement: application layer
```

## content_units (replaces pages)

```sql
CREATE TABLE content_units (
  id                    TEXT PRIMARY KEY,
  section_id            TEXT NOT NULL REFERENCES content_sections(id) ON DELETE CASCADE,
  unit_index            INTEGER NOT NULL,   -- 0-based, gaps allowed
  unit_type             TEXT NOT NULL CHECK (unit_type IN ('image','text','pdf_page','markdown','html')),
  -- image units
  storage_object_id     TEXT REFERENCES storage_objects(id) ON DELETE SET NULL,
  mime_type             TEXT,
  width                 INTEGER,
  height                INTEGER,
  checksum              TEXT,
  -- text units
  text_content          TEXT,
  text_hash             TEXT,
  -- provenance
  section_source_link_id TEXT REFERENCES section_source_links(id) ON DELETE SET NULL,
  created_at            TEXT NOT NULL,
  updated_at            TEXT NOT NULL,
  UNIQUE (section_id, unit_index)
);
CREATE INDEX idx_units_storage_object    ON content_units(storage_object_id);
CREATE INDEX idx_units_section_source   ON content_units(section_source_link_id);
```

## source_platforms

```sql
CREATE TABLE source_platforms (
  id            TEXT PRIMARY KEY,
  canonical_key TEXT NOT NULL UNIQUE,
  display_name  TEXT NOT NULL,
  kind          TEXT NOT NULL CHECK (kind IN ('local','remote','virtual')),
  status        TEXT NOT NULL CHECK (status IN ('active','disabled','deprecated')),
  created_at    TEXT NOT NULL,
  updated_at    TEXT NOT NULL
);
-- Status transitions enforced at application layer
-- deprecated → active and deprecated → disabled: REJECTED
```

## source_links

```sql
CREATE TABLE source_links (
  id                TEXT PRIMARY KEY,
  content_id        TEXT NOT NULL REFERENCES contents(id) ON DELETE CASCADE,
  source_platform_id TEXT NOT NULL REFERENCES source_platforms(id) ON DELETE RESTRICT,
  remote_work_id    TEXT NOT NULL,
  remote_url        TEXT,
  display_title     TEXT,
  link_status       TEXT NOT NULL CHECK (link_status IN ('active','candidate','rejected','stale')),
  confidence        TEXT NOT NULL CHECK (confidence IN ('manual','auto_high','auto_low')),
  created_at        TEXT NOT NULL,
  updated_at        TEXT NOT NULL
);
CREATE UNIQUE INDEX ux_source_links_platform_work ON source_links(source_platform_id, remote_work_id);
CREATE INDEX idx_source_links_content            ON source_links(content_id);
```

## section_source_links (replaces chapter_source_links)

```sql
CREATE TABLE section_source_links (
  id                TEXT PRIMARY KEY,
  section_id        TEXT NOT NULL REFERENCES content_sections(id) ON DELETE CASCADE,
  source_link_id    TEXT NOT NULL REFERENCES source_links(id) ON DELETE CASCADE,
  remote_section_id TEXT NOT NULL,
  remote_url        TEXT,
  remote_label      TEXT,
  source_order      INTEGER,   -- NULL = no order signal; MIN() across active = canonical sort
  link_status       TEXT NOT NULL CHECK (link_status IN ('active','inactive','stale')),
  confidence        TEXT NOT NULL CHECK (confidence IN ('manual','auto_high','auto_low')),
  created_at        TEXT NOT NULL,
  updated_at        TEXT NOT NULL
);
CREATE UNIQUE INDEX ux_ssl_source_section ON section_source_links(source_link_id, remote_section_id);
CREATE INDEX idx_ssl_section_id           ON section_source_links(section_id);
```

## content_unit_orders (replaces page_orders)

```sql
CREATE TABLE content_unit_orders (
  id         TEXT PRIMARY KEY,
  section_id TEXT NOT NULL REFERENCES content_sections(id) ON DELETE CASCADE,
  order_type TEXT NOT NULL CHECK (order_type IN ('source','user_override','import_detected','custom')),
  status     TEXT NOT NULL CHECK (status IN ('active','inactive','superseded','archived')),
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
CREATE UNIQUE INDEX ux_unit_orders_one_active
  ON content_unit_orders(section_id) WHERE status = 'active';
```

## content_unit_order_items (replaces page_order_items)

```sql
CREATE TABLE content_unit_order_items (
  id         TEXT PRIMARY KEY,
  order_id   TEXT NOT NULL REFERENCES content_unit_orders(id) ON DELETE CASCADE,
  unit_id    TEXT NOT NULL REFERENCES content_units(id) ON DELETE CASCADE,
  sort_index INTEGER NOT NULL,
  created_at TEXT NOT NULL,
  UNIQUE (order_id, sort_index),
  UNIQUE (order_id, unit_id)
);
```

## reading_sessions (replaces reader_sessions)

```sql
CREATE TABLE reading_sessions (
  id             TEXT PRIMARY KEY,
  content_id     TEXT NOT NULL UNIQUE REFERENCES contents(id) ON DELETE CASCADE,
  unit_id        TEXT NOT NULL REFERENCES content_units(id) ON DELETE RESTRICT,
  source_link_id TEXT REFERENCES source_links(id) ON DELETE SET NULL,
  session_state  TEXT NOT NULL CHECK (session_state IN ('active','suspended','completed','abandoned')),
  created_at     TEXT NOT NULL,
  updated_at     TEXT NOT NULL
);
-- unit_id ON DELETE RESTRICT: must clear reading session before cascading unit deletion
-- UNIQUE on content_id: one row per content, upserted
-- chapter_id and unit_index derived by joining content_units; never stored here
```

## user_collections

```sql
CREATE TABLE user_collections (
  id                      TEXT PRIMARY KEY,
  display_name            TEXT NOT NULL,
  description             TEXT,
  cover_storage_object_id TEXT REFERENCES storage_objects(id) ON DELETE SET NULL,
  sort_order              TEXT NOT NULL DEFAULT 'manual' CHECK (sort_order IN ('manual','title','updated_at','last_read')),
  created_at              TEXT NOT NULL,
  updated_at              TEXT NOT NULL
);
```

## user_collection_items

```sql
CREATE TABLE user_collection_items (
  id            TEXT PRIMARY KEY,
  collection_id TEXT NOT NULL REFERENCES user_collections(id) ON DELETE CASCADE,
  content_id    TEXT NOT NULL REFERENCES contents(id) ON DELETE CASCADE,
  sort_index    INTEGER NOT NULL,
  pinned_at     TEXT,
  added_at      TEXT NOT NULL,
  UNIQUE (collection_id, content_id),
  UNIQUE (collection_id, sort_index)
);
CREATE INDEX idx_collection_items_content ON user_collection_items(content_id);
```

## storage_backends

```sql
CREATE TABLE storage_backends (
  id                    TEXT PRIMARY KEY,
  backend_key           TEXT NOT NULL UNIQUE,
  display_name          TEXT NOT NULL,
  backend_kind          TEXT NOT NULL CHECK (backend_kind IN ('local_app_data','webdav','plugin','future')),
  config_json           TEXT NOT NULL,   -- NO plaintext secrets
  config_schema_version INTEGER NOT NULL,
  secret_ref            TEXT,            -- OS keychain ref only
  status                TEXT NOT NULL CHECK (status IN ('active','disabled','deprecated')),
  created_at            TEXT NOT NULL,
  updated_at            TEXT NOT NULL
);
```

## storage_objects

```sql
CREATE TABLE storage_objects (
  id           TEXT PRIMARY KEY,
  object_kind  TEXT NOT NULL CHECK (object_kind IN ('unit_image','cover','archive','backup','cache')),
  content_hash TEXT,
  size_bytes   INTEGER,
  mime_type    TEXT,
  created_at   TEXT NOT NULL,
  updated_at   TEXT NOT NULL
);
```

## storage_placements

```sql
CREATE TABLE storage_placements (
  id                 TEXT PRIMARY KEY,
  storage_object_id  TEXT NOT NULL REFERENCES storage_objects(id) ON DELETE CASCADE,
  storage_backend_id TEXT NOT NULL REFERENCES storage_backends(id) ON DELETE RESTRICT,
  object_key         TEXT NOT NULL,
  role               TEXT NOT NULL CHECK (role IN ('authority','cache','mirror','staging')),
  sync_status        TEXT NOT NULL CHECK (sync_status IN ('pending','uploading','synced','failed','evicted')),
  last_verified_at   TEXT,
  created_at         TEXT NOT NULL,
  updated_at         TEXT NOT NULL,
  UNIQUE (storage_object_id, storage_backend_id, object_key)
);
-- At most one authority per storage object
CREATE UNIQUE INDEX ux_placements_one_authority
  ON storage_placements(storage_object_id) WHERE role = 'authority';
```

## content_relationships

```sql
CREATE TABLE content_relationships (
  id                   TEXT PRIMARY KEY,
  source_content_id    TEXT NOT NULL REFERENCES contents(id) ON DELETE CASCADE,
  target_content_id    TEXT NOT NULL REFERENCES contents(id) ON DELETE CASCADE,
  relationship_type    TEXT NOT NULL CHECK (relationship_type IN ('translation','edition','sequel','prequel','spin_off','adaptation','alternative','colored')),
  source_language      TEXT,
  target_language      TEXT,
  source_content_type  TEXT NOT NULL,
  target_content_type  TEXT NOT NULL,
  confidence           TEXT NOT NULL CHECK (confidence IN ('manual','auto_high','auto_low')),
  evidence_signals_json TEXT NOT NULL DEFAULT '[]',
  created_at           TEXT NOT NULL,
  updated_at           TEXT NOT NULL,
  UNIQUE (source_content_id, target_content_id, relationship_type),
  CHECK (source_content_id != target_content_id)
);
CREATE INDEX idx_relationships_source ON content_relationships(source_content_id);
CREATE INDEX idx_relationships_target ON content_relationships(target_content_id);
```

## content_relationship_proposals

```sql
CREATE TABLE content_relationship_proposals (
  id                 TEXT PRIMARY KEY,
  source_content_id  TEXT NOT NULL REFERENCES contents(id) ON DELETE CASCADE,
  target_content_id  TEXT NOT NULL REFERENCES contents(id) ON DELETE CASCADE,
  suggested_type     TEXT NOT NULL,
  confidence         TEXT NOT NULL DEFAULT 'auto_low',
  signal_summary_json TEXT NOT NULL,
  status             TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','accepted','rejected','expired')),
  reviewed_at        TEXT,
  expires_at         TEXT NOT NULL,
  created_at         TEXT NOT NULL
);
```

## content_fingerprints

```sql
CREATE TABLE content_fingerprints (
  id               TEXT PRIMARY KEY,
  content_id       TEXT NOT NULL UNIQUE REFERENCES contents(id) ON DELETE CASCADE,
  cover_phash      TEXT,
  cover_dhash      TEXT,
  section_count    INTEGER NOT NULL DEFAULT 0,
  unit_count_hint  INTEGER NOT NULL DEFAULT 0,
  external_ids_json TEXT NOT NULL DEFAULT '{}',
  signal_version   TEXT NOT NULL,
  created_at       TEXT NOT NULL,
  updated_at       TEXT NOT NULL
);
```

## content_vectors

```sql
CREATE TABLE content_vectors (
  content_id       TEXT PRIMARY KEY REFERENCES contents(id) ON DELETE CASCADE,
  title_vec        BLOB,    -- float32[384]
  tag_vec          BLOB,    -- float32[N]
  content_rank     REAL NOT NULL DEFAULT 0.0,
  last_computed_at TEXT NOT NULL,
  signal_version   TEXT NOT NULL
);
-- SQLite: uses sqlite-vec extension
-- PostgreSQL: replace with vector(384) + HNSW index
```

## Auth tables

```sql
CREATE TABLE auth_users (
  id           TEXT PRIMARY KEY,
  display_name TEXT NOT NULL,
  role         TEXT NOT NULL CHECK (role IN ('owner','admin','viewer')),
  status       TEXT NOT NULL CHECK (status IN ('active','suspended','removed')),
  created_at   TEXT NOT NULL,
  updated_at   TEXT NOT NULL
);

CREATE TABLE auth_sessions (
  id           TEXT PRIMARY KEY,
  user_id      TEXT NOT NULL REFERENCES auth_users(id) ON DELETE CASCADE,
  method       TEXT NOT NULL CHECK (method IN ('passkey','oauth','api_key','local_password','magic_link')),
  token_hash   TEXT NOT NULL UNIQUE,   -- argon2, write-once
  expires_at   TEXT NOT NULL,
  last_used_at TEXT,
  ip_hash      TEXT,                   -- one-way, anomaly detection only
  user_agent   TEXT,
  created_at   TEXT NOT NULL
);
CREATE INDEX idx_sessions_user_id    ON auth_sessions(user_id);
CREATE INDEX idx_sessions_expires_at ON auth_sessions(expires_at);

CREATE TABLE passkeys (
  id            TEXT PRIMARY KEY,
  user_id       TEXT NOT NULL REFERENCES auth_users(id) ON DELETE CASCADE,
  credential_id TEXT NOT NULL UNIQUE,
  public_key    TEXT NOT NULL,
  sign_count    INTEGER NOT NULL DEFAULT 0,
  device_name   TEXT NOT NULL,
  aaguid        TEXT,
  last_used_at  TEXT,
  created_at    TEXT NOT NULL
);

CREATE TABLE api_keys (
  id           TEXT PRIMARY KEY,
  user_id      TEXT NOT NULL REFERENCES auth_users(id) ON DELETE CASCADE,
  key_hash     TEXT NOT NULL UNIQUE,
  display_name TEXT NOT NULL,
  scopes_json  TEXT NOT NULL,
  expires_at   TEXT,
  last_used_at TEXT,
  revoked_at   TEXT,
  created_at   TEXT NOT NULL
);

CREATE TABLE oauth_connections (
  id                   TEXT PRIMARY KEY,
  user_id              TEXT NOT NULL REFERENCES auth_users(id) ON DELETE CASCADE,
  provider             TEXT NOT NULL CHECK (provider IN ('google','github','discord','custom_oidc')),
  provider_user_id     TEXT NOT NULL,
  provider_email_hash  TEXT,
  access_token_ref     TEXT NOT NULL,   -- secretRef, NOT raw token
  refresh_token_ref    TEXT NOT NULL,   -- secretRef, NOT raw token
  token_expires_at     TEXT NOT NULL,
  created_at           TEXT NOT NULL,
  updated_at           TEXT NOT NULL,
  UNIQUE (user_id, provider, provider_user_id)
);

CREATE TABLE ws_tickets (
  ticket      TEXT PRIMARY KEY,
  user_id     TEXT NOT NULL REFERENCES auth_users(id) ON DELETE CASCADE,
  scopes_json TEXT NOT NULL,
  expires_at  TEXT NOT NULL,
  used        INTEGER NOT NULL DEFAULT 0,
  created_at  TEXT NOT NULL
);
```

## Audit tables (append-only)

```sql
CREATE TABLE audit_events (
  id              TEXT PRIMARY KEY,
  seq             INTEGER NOT NULL,
  stream_id       TEXT NOT NULL,
  event_id        TEXT NOT NULL UNIQUE,    -- dedup replays
  schema_version  TEXT NOT NULL DEFAULT '1.0.0',
  actor_kind      TEXT NOT NULL CHECK (actor_kind IN ('user','system','plugin','api_key')),
  actor_id        TEXT NOT NULL,
  actor_role      TEXT,
  actor_ip_hash   TEXT,
  recorded_at     TEXT NOT NULL,
  idempotency_key TEXT,
  payload_json    TEXT NOT NULL,           -- TIER 2 fields only
  payload_hash    TEXT NOT NULL,
  prev_hash       TEXT,                    -- NULL = stream-first event
  event_core      TEXT NOT NULL,
  event_hash      TEXT NOT NULL UNIQUE,
  signature       TEXT NOT NULL,
  signing_key_id  TEXT NOT NULL,
  UNIQUE (stream_id, seq)
);
-- NO UPDATE, NO DELETE exposed by repository port
CREATE INDEX idx_audit_stream_seq  ON audit_events(stream_id, seq);
CREATE INDEX idx_audit_recorded_at ON audit_events(recorded_at);
CREATE INDEX idx_audit_event_name  ON audit_events(stream_id);

CREATE TABLE audit_checkpoints (
  id              TEXT PRIMARY KEY,
  checkpoint_seq  INTEGER NOT NULL UNIQUE,
  streams_json    TEXT NOT NULL,
  merkle_root     TEXT NOT NULL,
  event_count     INTEGER NOT NULL,
  signature       TEXT NOT NULL,
  signing_key_id  TEXT NOT NULL,
  created_at      TEXT NOT NULL
);
-- Store in separate DB from audit_events for independence guarantee
```

## Telemetry & Reporting tables

```sql
CREATE TABLE telemetry_consent (
  id              TEXT PRIMARY KEY,
  consent_type    TEXT NOT NULL CHECK (consent_type IN ('crash_report','community_telemetry','plugin_reporting','feedback')),
  given           INTEGER NOT NULL CHECK (given IN (0,1)),
  policy_version  TEXT NOT NULL,
  given_at        TEXT,
  revoked_at      TEXT,
  created_at      TEXT NOT NULL,
  updated_at      TEXT NOT NULL
);
-- At most one active consent per type; new policy version = new row

CREATE TABLE reading_events (
  id              TEXT PRIMARY KEY,
  content_id      TEXT NOT NULL REFERENCES contents(id) ON DELETE CASCADE,
  section_id      TEXT NOT NULL REFERENCES content_sections(id) ON DELETE CASCADE,
  session_id      TEXT NOT NULL,    -- anonymous, rotates daily
  completion_rate REAL NOT NULL CHECK (completion_rate BETWEEN 0 AND 1),
  duration_ms     INTEGER,
  recorded_at     TEXT NOT NULL
);

CREATE TABLE recommendation_feedback (
  id               TEXT PRIMARY KEY,
  source_content_id TEXT NOT NULL,
  target_content_id TEXT NOT NULL,
  action           TEXT NOT NULL CHECK (action IN ('click','dismiss','save')),
  algorithm        TEXT NOT NULL,
  rank             INTEGER,
  recorded_at      TEXT NOT NULL
);

CREATE TABLE training_signals (
  id           TEXT PRIMARY KEY,
  signal_type  TEXT NOT NULL,
  payload_json TEXT NOT NULL,
  processed    INTEGER NOT NULL DEFAULT 0,
  recorded_at  TEXT NOT NULL
);
CREATE INDEX idx_signals_unprocessed ON training_signals(processed, recorded_at) WHERE processed = 0;
```

## Plugin & Package tables

```sql
CREATE TABLE source_repositories (
  id                      TEXT PRIMARY KEY,
  display_name            TEXT NOT NULL,
  primary_url             TEXT NOT NULL,
  mirror_urls_json        TEXT NOT NULL DEFAULT '[]',
  public_key_fingerprint  TEXT NOT NULL,
  public_key_material     TEXT NOT NULL,
  trust_tier              TEXT NOT NULL CHECK (trust_tier IN ('official','community','self_hosted')),
  discovery_method        TEXT NOT NULL CHECK (discovery_method IN ('builtin','mdns','url_scheme','dns_txt','manual')),
  status                  TEXT NOT NULL CHECK (status IN ('active','disabled')),
  last_index_synced_at    TEXT,
  created_at              TEXT NOT NULL,
  updated_at              TEXT NOT NULL
);

CREATE TABLE source_package_artifacts (
  id                TEXT PRIMARY KEY,
  source_platform_id TEXT REFERENCES source_platforms(id) ON DELETE SET NULL,
  package_key       TEXT NOT NULL,
  provider_key      TEXT NOT NULL,
  version           TEXT NOT NULL,
  archive_sha256    TEXT NOT NULL,
  package_store_ref TEXT NOT NULL,
  state             TEXT NOT NULL CHECK (state IN ('committed','active','orphaned','cleanup_pending','removed')),
  verification_tier TEXT NOT NULL CHECK (verification_tier IN ('official','community','custom','unverified')),
  created_at        TEXT NOT NULL,
  updated_at        TEXT NOT NULL
);
```

## Misc tables

```sql
CREATE TABLE operation_idempotency (
  operation_name       TEXT NOT NULL,
  idempotency_key      TEXT NOT NULL,
  input_hash           TEXT NOT NULL,
  status               TEXT NOT NULL CHECK (status IN ('in_progress','completed','failed')),
  result_type          TEXT,
  result_resource_id   TEXT,
  result_json          TEXT,
  result_schema_version TEXT,
  created_at           TEXT NOT NULL,
  updated_at           TEXT NOT NULL,
  PRIMARY KEY (operation_name, idempotency_key)
);
-- TODO: TTL cleanup job for stale in_progress and failed records

CREATE TABLE setup_state (
  id               TEXT PRIMARY KEY DEFAULT 'singleton',
  completed_steps  TEXT NOT NULL DEFAULT '[]',
  is_complete      INTEGER NOT NULL DEFAULT 0,
  completed_at     TEXT,
  instance_name    TEXT,
  deployment_mode  TEXT CHECK (deployment_mode IN ('standalone','hosted')),
  created_at       TEXT NOT NULL,
  updated_at       TEXT NOT NULL
);

CREATE TABLE client_network_config (
  id                     TEXT PRIMARY KEY DEFAULT 'singleton',
  global_proxy           TEXT,
  proxies_json           TEXT NOT NULL DEFAULT '[]',
  dns_json               TEXT NOT NULL,
  rules_json             TEXT NOT NULL DEFAULT '[]',
  source_rules_json      TEXT NOT NULL DEFAULT '{}',
  config_schema_version  INTEGER NOT NULL,
  updated_at             TEXT NOT NULL
);

-- Tags
CREATE TABLE canonical_tags (
  id          TEXT PRIMARY KEY,   -- = CanonicalTagKey e.g. "genre:action"
  namespace   TEXT NOT NULL,
  tag_key     TEXT NOT NULL,
  created_at  TEXT NOT NULL,
  UNIQUE (namespace, tag_key)
);

CREATE TABLE source_tags (
  id               TEXT PRIMARY KEY,
  source_link_id   TEXT NOT NULL REFERENCES source_links(id) ON DELETE CASCADE,
  raw_tag          TEXT NOT NULL,
  canonical_tag_id TEXT REFERENCES canonical_tags(id) ON DELETE SET NULL,
  confidence       TEXT NOT NULL CHECK (confidence IN ('manual','auto_high','auto_low')),
  created_at       TEXT NOT NULL,
  UNIQUE (source_link_id, raw_tag)
);

CREATE TABLE user_tags (
  id         TEXT PRIMARY KEY,
  label      TEXT NOT NULL,
  color      TEXT,
  created_at TEXT NOT NULL
);

CREATE TABLE content_user_tags (
  content_id TEXT NOT NULL REFERENCES contents(id) ON DELETE CASCADE,
  tag_id     TEXT NOT NULL REFERENCES user_tags(id) ON DELETE CASCADE,
  added_at   TEXT NOT NULL,
  PRIMARY KEY (content_id, tag_id)
);

-- Note-specific
CREATE TABLE note_links (
  id               TEXT PRIMARY KEY,
  source_content_id TEXT NOT NULL REFERENCES contents(id) ON DELETE CASCADE,
  target_content_id TEXT NOT NULL REFERENCES contents(id) ON DELETE CASCADE,
  link_text        TEXT NOT NULL,
  resolved         INTEGER NOT NULL DEFAULT 0,
  created_at       TEXT NOT NULL
);

CREATE TABLE content_annotations (
  id              TEXT PRIMARY KEY,
  content_id      TEXT NOT NULL REFERENCES contents(id) ON DELETE CASCADE,
  unit_id         TEXT NOT NULL REFERENCES content_units(id) ON DELETE CASCADE,
  annotation_type TEXT NOT NULL CHECK (annotation_type IN ('highlight','comment','bookmark')),
  start_offset    INTEGER NOT NULL,
  end_offset      INTEGER NOT NULL,
  color           TEXT,
  comment         TEXT,
  created_at      TEXT NOT NULL,
  updated_at      TEXT NOT NULL
);

-- Full-text search (text content types only)
CREATE VIRTUAL TABLE content_fts USING fts5(
  content_id   UNINDEXED,
  unit_id      UNINDEXED,
  text_content,
  tokenize = "unicode61"
);
```

## Legacy guardrails (do NOT use)

The following patterns must not appear in new code:
- `comic_id` column naming → use `content_id`
- `chapter_id` → `section_id`
- `page_id` → `unit_id`
- `is_active` boolean → use `status` enum
- `page_count` cached field on orders → derive from items
- `order_key` field → removed, use `order_type` only
- `sort_order` on items → use `sort_index`
- `is_hidden` on items → removed
- `active_tab_position` on sessions → removed
- filesystem path columns → use storage abstraction
- raw `source_key` as identity → use `canonicalKey` + `remoteWorkId`
