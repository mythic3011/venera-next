# Venera Database Schema
> Pre-stable. Logical schema with SQLite reference mapping.
> Type column = corrected SQLite target. Future backends must map explicitly.
> **Schema authority.** This file is the single source of truth for all canonical tables. Feature/plugin docs (05, 07) may show `CREATE TABLE` blocks for context, but those are **target fragments pending consolidation here** and are not independently authoritative — on conflict, this file wins.

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
  content_rating          TEXT CHECK (content_rating IN ('safe','moderate','adult_only','explicit')),
  user_rating             INTEGER CHECK (user_rating BETWEEN 1 AND 5),
  metadata_json           TEXT,
  created_at              TEXT NOT NULL,
  updated_at              TEXT NOT NULL
);
-- cover conflict rule: if both refs present, cover_unit_id.storage_object_id must equal cover_storage_object_id
-- enforced at application layer
-- cover unit deletion rule: ON DELETE SET NULL is allowed only when the remaining
-- cover_storage_object_id keeps cover_status valid, or the deleting transaction
-- resets cover_status = 'none' and clears both refs. It must not leave
-- local_only with no local cover reference.
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
-- AT MOST one primary per content (DB-enforced)
CREATE UNIQUE INDEX ux_content_titles_one_primary
  ON content_titles(content_id) WHERE title_kind = 'primary';
-- SQLite-specific logical uniqueness with value-bearing NULL buckets.
-- Sentinels are internal index keys and must not be accepted as locale/source IDs.
CREATE UNIQUE INDEX ux_content_titles_logical
  ON content_titles(
    content_id,
    normalized_title,
    COALESCE(locale, '__venera_null_locale__'),
    COALESCE(source_platform_id, '__venera_null_source_platform__')
  );
```

Notes:
- The partial unique index enforces **at most one** primary title; it cannot enforce **at least one**. Title create/update/delete use cases must enforce the minimum-one-primary invariant in the same transaction that maintains `content_metadata.title`.
- LOGICAL UNIQUE rule on `(content_id, normalized_title, locale, source_platform_id)`: missing `locale` / missing `source_platform_id` are value-bearing buckets (NULL is **not** "duplicates allowed"). SQLite enforces this through `ux_content_titles_logical`; other backends must use equivalent expression/functional indexes or a named transaction guard.
- `content_metadata.title` is a denormalized cache of the primary title; both must be written atomically. A future server-backed multi-writer backend must add DB-level enforcement (trigger or `primary_title_id` authority) or drop the cache.

## content_sections (replaces chapters)

```sql
CREATE TABLE content_sections (
  id                TEXT PRIMARY KEY,
  content_id        TEXT NOT NULL REFERENCES contents(id) ON DELETE CASCADE,
  parent_section_id TEXT REFERENCES content_sections(id)
                      ON DELETE NO ACTION DEFERRABLE INITIALLY DEFERRED,
  section_kind      TEXT NOT NULL CHECK (section_kind IN ('season','volume','chapter','episode','oneshot','group','section','entry','article','part')),
  section_number    TEXT,   -- DecimalString, nullable, non-unique, ordering hint only
  title             TEXT,
  display_label     TEXT,
  created_at        TEXT NOT NULL,
  updated_at        TEXT NOT NULL
);
CREATE INDEX idx_sections_content_id      ON content_sections(content_id);
CREATE INDEX idx_sections_parent          ON content_sections(parent_section_id);
-- section_number compared with decimal/numeric semantics — never lexicographic,
-- never binary floating point (CAST AS REAL is acceptable only if precision loss is proven safe for the value range)
-- cycle/self-parent/max-depth-8 enforcement: application layer, fail closed
-- Parent deletion must NOT silently promote children to root (this is why the FK is
-- NOT "ON DELETE SET NULL"). Delete use cases must pick an explicit mode:
-- delete_subtree | reparent_children | reject_if_children.
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

Notes:
- Lifecycle is update-in-place across `active | candidate | rejected | stale`. A rejected/stale row does **not** free `(source_platform_id, remote_work_id)` for a second row. If append-only provenance history is ever needed, this uniqueness model must change first.
- `Content.origin_hint` must be recomputed in the **same transaction** as any source-link membership/status change.

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

Source-order aggregation rule: canonical source order for a section is `MIN(source_order)` across links where `section_source_links.link_status = 'active'` AND parent `source_links.link_status = 'active'` AND parent `source_platforms.status = 'active'`, with non-null `source_order`. If no qualifying link exists, source order is absent. Used by first-canonical-section reader fallback (see `03_USE_CASES.md`).

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
  content_id     TEXT NOT NULL REFERENCES contents(id) ON DELETE CASCADE,
  unit_id        TEXT NOT NULL REFERENCES content_units(id)
                   ON DELETE NO ACTION DEFERRABLE INITIALLY DEFERRED,
  source_link_id TEXT REFERENCES source_links(id) ON DELETE SET NULL,
  session_state  TEXT NOT NULL CHECK (session_state IN ('active','suspended','completed','abandoned')),
  created_at     TEXT NOT NULL,
  updated_at     TEXT NOT NULL
);
CREATE INDEX idx_reading_sessions_content ON reading_sessions(content_id);
CREATE INDEX idx_reading_sessions_source  ON reading_sessions(source_link_id);
-- AT MOST ONE ACTIVE session per content; non-active rows are lifecycle history
CREATE UNIQUE INDEX ux_reading_sessions_one_active
  ON reading_sessions(content_id) WHERE session_state = 'active';
-- Position authority is unit_id; section_id and unit_index are DERIVED by joining
-- content_units — never stored here.
-- unit_id FK must NOT be immediate RESTRICT: permanent Content purge must not depend
-- on undefined cascade ordering between reading_sessions and sections -> units.
-- Direct unit deletion while sessions reference it must fail unless the same
-- transaction first abandons/rewrites those sessions.
-- session_state is lifecycle state, not a boolean. Only 'active' rows are resume
-- candidates; 'completed'/'abandoned'/'suspended' rows are historical evidence
-- (Clear Position marks the active row 'abandoned' in place — no hard delete).
-- Writes are last-write-wins in the local single-runtime model; multi-device sync
-- requires an explicit conflict-resolution contract (see 07_FEATURES.md sync notes)
-- before any version/device_id columns become authority.
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
  plugin_key            TEXT,            -- required when backend_kind = 'plugin'; plugin table consolidation pending
  config_json           TEXT NOT NULL,   -- NO plaintext secrets
  config_schema_version INTEGER NOT NULL,
  secret_ref            TEXT,            -- OS keychain ref only
  status                TEXT NOT NULL CHECK (status IN ('active','disabled','deprecated')),
  created_at            TEXT NOT NULL,
  updated_at            TEXT NOT NULL,
  CHECK ((backend_kind = 'plugin' AND plugin_key IS NOT NULL)
      OR (backend_kind != 'plugin' AND plugin_key IS NULL))
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

Notes:
- Relationship rows are directed evidence. The database does not auto-create reverse edges; query/use-case code that wants symmetric "related content" behavior must search both `source_content_id` and `target_content_id` explicitly.

## content_relationship_proposals

```sql
CREATE TABLE content_relationship_proposals (
  id                 TEXT PRIMARY KEY,
  source_content_id  TEXT NOT NULL REFERENCES contents(id) ON DELETE CASCADE,
  target_content_id  TEXT NOT NULL REFERENCES contents(id) ON DELETE CASCADE,
  suggested_type     TEXT NOT NULL,
  confidence         TEXT NOT NULL DEFAULT 'auto_low' CHECK (confidence IN ('manual','auto_high','auto_low')),
  signal_summary_json TEXT NOT NULL,
  status             TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','accepted','rejected','expired')),
  reviewed_at        TEXT,
  expires_at         TEXT NOT NULL,
  created_at         TEXT NOT NULL,
  CHECK (source_content_id != target_content_id)
);
CREATE UNIQUE INDEX ux_relationship_proposals_pending
  ON content_relationship_proposals(source_content_id, target_content_id, suggested_type)
  WHERE status = 'pending';
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
  id           TEXT PRIMARY KEY,       -- = token selector (public half, random)
  user_id      TEXT NOT NULL REFERENCES auth_users(id) ON DELETE CASCADE,
  method       TEXT NOT NULL CHECK (method IN ('passkey','oauth','api_key','local_password','magic_link')),
  token_hash   TEXT NOT NULL,          -- HMAC-SHA256(verifier, serverKey); write-once
  key_id       TEXT NOT NULL,          -- HMAC server key id used for token_hash
  expires_at   TEXT NOT NULL,
  last_used_at TEXT,
  ip_hash      TEXT,                   -- one-way, anomaly detection only
  user_agent   TEXT,
  created_at   TEXT NOT NULL
);
CREATE INDEX idx_sessions_user_id    ON auth_sessions(user_id);
CREATE INDEX idx_sessions_expires_at ON auth_sessions(expires_at);
-- TOKEN SCHEME (selector.verifier):
--   issued token = "<selector>.<verifier>", both high-entropy random (>=128-bit verifier).
--   Lookup: SELECT by id = selector, then constant-time compare
--   HMAC-SHA256(verifier) with key_id-selected server key against token_hash.
-- WHY NOT argon2 here: argon2 output is salted/non-deterministic, so a UNIQUE
-- "look up row by hash of presented token" design cannot work, and slow hashing
-- of a high-entropy random token adds latency without security benefit.
-- argon2id is REQUIRED only for low-entropy user secrets (local_password, filter PIN).
-- Tokens are never stored plaintext, never logged, never returned after creation.
-- HMAC key management:
--   key material lives in OS/deployment secret storage, never in DB/config.
--   New credentials use the newest active key_id. Old key_ids remain verify-only
--   until their credentials expire or are explicitly revoked. A compromised key_id
--   can be hard-revoked, invalidating only credentials signed under that key.

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
  id           TEXT PRIMARY KEY,       -- = key selector embedded in "vk_<selector>_<verifier>"
  user_id      TEXT NOT NULL REFERENCES auth_users(id) ON DELETE CASCADE,
  key_hash     TEXT NOT NULL,          -- HMAC-SHA256(verifier); shown once at creation, never retrievable
  key_id       TEXT NOT NULL,          -- HMAC server key id used for key_hash
  display_name TEXT NOT NULL,
  scopes_json  TEXT NOT NULL,          -- immutable after creation
  expires_at   TEXT,
  last_used_at TEXT,
  revoked_at   TEXT,
  created_at   TEXT NOT NULL
);
-- Same selector/verifier scheme as auth_sessions (see note above).

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
  ticket_hash TEXT PRIMARY KEY,        -- SHA-256 of issued ticket; raw ticket never stored
  user_id     TEXT NOT NULL REFERENCES auth_users(id) ON DELETE CASCADE,
  scopes_json TEXT NOT NULL,
  expires_at  TEXT NOT NULL,           -- short TTL (<= 60s recommended)
  used        INTEGER NOT NULL DEFAULT 0,   -- single-use; consume atomically (UPDATE ... WHERE used = 0)
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
  anonymous_session_id TEXT NOT NULL,    -- anonymous, rotates daily
  completion_rate REAL NOT NULL CHECK (completion_rate BETWEEN 0 AND 1),
  duration_ms     INTEGER,
  recorded_at     TEXT NOT NULL
);
CREATE INDEX idx_reading_events_anon_session
  ON reading_events(anonymous_session_id, recorded_at);

CREATE TABLE recommendation_feedback (
  id               TEXT PRIMARY KEY,
  source_content_id TEXT NOT NULL,
  target_content_id TEXT NOT NULL,
  action           TEXT NOT NULL CHECK (action IN ('click','dismiss','save')),
  algorithm        TEXT NOT NULL,
  rank             INTEGER,
  recorded_at      TEXT NOT NULL
);
-- Intentionally NO FK to contents: feedback rows are behavioral training
-- evidence and must survive content deletion (same policy as training_signals).

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
  trust_tier              TEXT NOT NULL CHECK (trust_tier IN ('official','community','custom')),
  discovery_method        TEXT NOT NULL CHECK (discovery_method IN ('builtin','mdns','url_scheme','dns_txt','manual')),
  status                  TEXT NOT NULL CHECK (status IN ('active','disabled')),
  last_index_synced_at    TEXT,
  created_at              TEXT NOT NULL,
  updated_at              TEXT NOT NULL
);

CREATE TABLE source_package_artifacts (
  id                      TEXT PRIMARY KEY,
  source_platform_id      TEXT REFERENCES source_platforms(id) ON DELETE SET NULL,
  package_key             TEXT NOT NULL,
  provider_key            TEXT NOT NULL,
  version                 TEXT NOT NULL,
  archive_sha256          TEXT NOT NULL,   -- lowercase hex
  package_store_ref       TEXT NOT NULL,
  state                   TEXT NOT NULL CHECK (state IN ('committed','active','orphaned','cleanup_pending','removed')),
  verification_tier       TEXT NOT NULL CHECK (verification_tier IN ('official','community','custom','unverified')),
  publisher_key_fingerprint TEXT,          -- normalized public-key fingerprint (verification evidence)
  signature_digest        TEXT,            -- normalized signature evidence digest
  created_at              TEXT NOT NULL,
  updated_at              TEXT NOT NULL
);
-- Install-time verification evidence (verification_tier + publisher_key_fingerprint
-- + signature_digest) MUST be persisted; "signatureValid" must never be stored as a
-- mutable boolean. source_platform_id stays NULL until activation succeeds.
-- Lifecycle, lease timers, and commit-order rules: 08_SOURCE_PACKAGE_LIFECYCLE.md.
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
CREATE INDEX idx_op_idem_created ON operation_idempotency(operation_name, created_at);
-- CONTRACT (not a TODO — this is canonical):
--   input_hash = lowercase SHA-256 hex of canonical JSON input (sorted keys,
--     operation-defined defaults applied, volatile fields excluded).
--   same key + same input_hash + completed        -> replay stored result
--   same key + different input_hash               -> IDEMPOTENCY_CONFLICT, no mutation
--   same key + in_progress, lease not expired     -> fail closed (no block, no poll)
--   stale in_progress (updated_at + lease TTL expired) + same input_hash
--                                                  -> atomically reclaim key, then mutate
--   failed record + same input_hash               -> retry allowed only after retry TTL
--   completed records are terminal; status flow: in_progress -> completed | failed
--   completed requires replayable evidence: result_type + (result_resource_id | result_json);
--   result_schema_version required when result_json present.
--   Default lease TTL and retry TTL: 5 minutes from updated_at; long-running ops must
--   renew updated_at before lease expiry.
-- Cleanup: may purge stale failed / stale unclaimed in_progress after retention;
-- must NOT purge completed records before their replay retention window expires.

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
  start_offset    INTEGER,   -- required for highlight/comment; NULL allowed for bookmark (e.g. bookmark on an image unit)
  end_offset      INTEGER,
  color           TEXT,
  comment         TEXT,
  created_at      TEXT NOT NULL,
  updated_at      TEXT NOT NULL,
  CHECK (annotation_type = 'bookmark' OR (start_offset IS NOT NULL AND end_offset IS NOT NULL)),
  CHECK (start_offset IS NULL OR end_offset IS NULL OR end_offset >= start_offset)
);

-- Full-text search (text content types only)
CREATE VIRTUAL TABLE content_fts USING fts5(
  content_id   UNINDEXED,
  unit_id      UNINDEXED,
  text_content,
  tokenize = "unicode61"
);
```

## One-Time Legacy Distributed Import Tables (canonical schema authority)

These tables support a **separate trusted data-import operation** from the discarded old Venera distributed stores, not the general `import_jobs` plugin pipeline or the Deferred `ImportBatch`. Only `local.db`, `history.db`, `local_favorite.db`, `appdata.json` and `implicitData.json` are valid source metadata formats; legacy Unified Store `venera.db` is prohibited. SQLite journal sidecars are only consistency mechanisms during read-only source snapshots.

These are **reference target DDL** for the fresh v2 database. Install the subset in L0/L1 after M0/M1 as required; collection-target references become usable only once M2 collection tables exist. All physical legacy input access is isolated from SQL repositories. The trusted application layer additionally checks user/tenant scope, file signatures, JSON schemas, record hashes and path grants. SQLite checks alone cannot enforce those rules.

~~~sql
CREATE TABLE legacy_import_datasets (
  id             TEXT PRIMARY KEY,            -- fresh UUID v4, not input-path/hash
  owner_scope_id TEXT NOT NULL,               -- trusted Venera principal; runtime verifies scope
  display_label  TEXT NOT NULL,
  state          TEXT NOT NULL DEFAULT 'active'
                  CHECK (state IN ('active','archived')),
  created_at     TEXT NOT NULL,
  updated_at     TEXT NOT NULL
);
CREATE INDEX idx_legacy_dataset_owner ON legacy_import_datasets(owner_scope_id,state);

CREATE TABLE legacy_import_batches (
  id                   TEXT PRIMARY KEY,
  dataset_id           TEXT NOT NULL REFERENCES legacy_import_datasets(id) ON DELETE RESTRICT,
  input_manifest_json  TEXT NOT NULL,          -- approved five-role snapshot digests and options, no raw credentials
  policy_revision      TEXT NOT NULL,
  plan_digest          TEXT NOT NULL,          -- approved plan; batch fingerprint ≠ record identity
  approval_scope       TEXT NOT NULL DEFAULT 'evidence_only'
                       CHECK (approval_scope IN ('evidence_only')), -- no Content/Storage write permission
  snapshot_lease_ref   TEXT,                   -- host-private ephemeral ref; mandatory to execute approved work
  state                TEXT NOT NULL DEFAULT 'selected'
                       CHECK (state IN
                         ('selected','snapshotted','previewed','approved','applying',
                          'verified','partial','failed','cancelled')),
  created_at           TEXT NOT NULL,
  approved_at          TEXT,
  completed_at         TEXT,
  updated_at           TEXT NOT NULL,
  CHECK ((state IN ('verified','partial','failed','cancelled') AND completed_at IS NOT NULL)
      OR (state NOT IN ('verified','partial','failed','cancelled') AND completed_at IS NULL))
);
CREATE INDEX idx_legacy_batches_dataset ON legacy_import_batches(dataset_id,created_at);

CREATE TABLE legacy_record_mappings (
  id                   TEXT PRIMARY KEY,      -- stable trusted assignment, UUID v4
  dataset_id           TEXT NOT NULL REFERENCES legacy_import_datasets(id) ON DELETE RESTRICT,
  file_role            TEXT NOT NULL
                       CHECK (file_role IN
                         ('local.db','history.db','local_favorite.db',
                          'appdata.json','implicitData.json')),
  table_kind           TEXT NOT NULL,          -- normalized table or JSON namespace
  scope_key            TEXT NOT NULL DEFAULT '',-- normalized folder/table scope; never NULL
  legacy_type_key      TEXT NOT NULL DEFAULT '',-- normalized comic type/source key; never NULL
  legacy_id            TEXT NOT NULL,          -- old ID or JSON setting key
  source_record_digest TEXT NOT NULL,          -- version evidence, NOT identity
  mapping_state        TEXT NOT NULL CHECK (mapping_state IN
                       ('mapped','unchanged','changed_pending','conflict','unresolved','tombstoned')),
  target_content_id    TEXT REFERENCES contents(id) ON DELETE SET NULL,
  target_section_id    TEXT REFERENCES content_sections(id) ON DELETE SET NULL,
  target_unit_id       TEXT REFERENCES content_units(id) ON DELETE SET NULL,
  target_collection_id TEXT REFERENCES user_collections(id) ON DELETE SET NULL,
  target_item_id       TEXT REFERENCES user_collection_items(id) ON DELETE SET NULL,
  last_batch_id        TEXT REFERENCES legacy_import_batches(id) ON DELETE SET NULL,
  evidence_revision    INTEGER NOT NULL DEFAULT 1 CHECK (evidence_revision > 0),
  created_at           TEXT NOT NULL,
  updated_at           TEXT NOT NULL,
  UNIQUE (dataset_id,file_role,table_kind,scope_key,legacy_type_key,legacy_id),
  CHECK (length(table_kind)>0 AND length(legacy_id)>0),
  -- One canonical target per record. Preference keys may have zero target FKs.
  CHECK (
      (target_content_id IS NOT NULL)
    + (target_section_id IS NOT NULL)
    + (target_unit_id IS NOT NULL)
    + (target_collection_id IS NOT NULL)
    + (target_item_id IS NOT NULL) <= 1
  )
);
CREATE INDEX idx_legacy_mappings_batch ON legacy_record_mappings(last_batch_id);
CREATE INDEX idx_legacy_mappings_content ON legacy_record_mappings(target_content_id);
-- Storage/application contract: never treat mapping_state='mapped' with a missing
-- canonical target as successful content import (preference evidence is the
-- explicitly permitted targetless case). On explicit canonical deletion, detach/tombstone
-- affected mappings in the same use-case transaction; never resurrect silently.

CREATE TABLE legacy_unresolved_records (
  id                     TEXT PRIMARY KEY,
  batch_id               TEXT NOT NULL REFERENCES legacy_import_batches(id) ON DELETE RESTRICT,
  mapping_id             TEXT REFERENCES legacy_record_mappings(id) ON DELETE SET NULL,
  category               TEXT NOT NULL CHECK (category IN
                         ('work','reader_position','favorite','image_favorite',
                          'tag','preference','source_reference','media')),
  reason_code            TEXT NOT NULL,
  evidence_json          TEXT NOT NULL,       -- bounded schema-validated private *non-secret* evidence
  next_eligible_milestone TEXT,
  state                  TEXT NOT NULL DEFAULT 'pending'
                         CHECK (state IN ('pending','resolved','skipped','dismissed')),
  resolved_target_id     TEXT,                -- typed evidence only; not identity authority
  created_at             TEXT NOT NULL,
  updated_at             TEXT NOT NULL
);
CREATE INDEX idx_legacy_unresolved_batch
  ON legacy_unresolved_records(batch_id,state,category);
CREATE UNIQUE INDEX ux_legacy_unresolved_active
  ON legacy_unresolved_records(batch_id,mapping_id,category)
  WHERE state='pending' AND mapping_id IS NOT NULL;

CREATE TABLE legacy_asset_journal (
  id                      TEXT PRIMARY KEY,
  batch_id                TEXT NOT NULL REFERENCES legacy_import_batches(id) ON DELETE RESTRICT,
  mapping_id              TEXT REFERENCES legacy_record_mappings(id) ON DELETE SET NULL,
  planned_storage_id      TEXT NOT NULL,      -- reserved v2 UUID, no object row before DB visibility commit
  committed_storage_id    TEXT REFERENCES storage_objects(id) ON DELETE SET NULL,
  staging_ref             TEXT NOT NULL,      -- opaque importer-owned private staging handle
  promoted_ref            TEXT,              -- opaque importer-owned managed location handle
  expected_sha256         TEXT NOT NULL,      -- checked against actual bytes
  expected_bytes          INTEGER NOT NULL CHECK (expected_bytes >= 0),
  state                   TEXT NOT NULL CHECK (state IN
                          ('planned','staged','verified','promoted','committed','gc_pending')),
  authorization_scope     TEXT NOT NULL DEFAULT 'plan_only'
                          CHECK (authorization_scope IN ('plan_only')),
  authorization_digest    TEXT NOT NULL,       -- separate human-approved asset intent, not Batch plan digest
  CHECK (authorization_scope != 'plan_only' OR state = 'planned'), -- cannot stage/promote with plan-only grant
  created_at              TEXT NOT NULL,
  updated_at              TEXT NOT NULL,
  UNIQUE (batch_id,planned_storage_id)
);
CREATE INDEX idx_legacy_journal_recovery ON legacy_asset_journal(batch_id,state);
-- Preflight asset intent is one digest per mapped old work per Batch.
-- A future chapter/page importer needs independently reviewed page identity
-- and a new scope/schema before it can create multiple active placements.
CREATE UNIQUE INDEX ux_legacy_planned_asset_mapping
  ON legacy_asset_journal(batch_id,mapping_id,expected_sha256)
  WHERE state='planned' AND mapping_id IS NOT NULL;

CREATE TABLE legacy_import_receipts (
  batch_id             TEXT PRIMARY KEY REFERENCES legacy_import_batches(id) ON DELETE RESTRICT,
  state                TEXT NOT NULL CHECK (state IN ('verified','partial','failed','cancelled')),
  counters_json        TEXT NOT NULL,         -- derived from committed mapping and journal state
  policy_revision      TEXT NOT NULL,
  finalized_at         TEXT NOT NULL,         -- can be partial/failed/cancelled; not always verified
  created_at           TEXT NOT NULL
);
~~~

**Canonical write/transaction semantics (mandatory):**
1. `LegacyRecordKey` normalization uses all six **non-null** identity components. `scope_key` and `legacy_type_key` are literal empty strings only when their scopes do not apply, never SQL NULL. File role is an enum, not arbitrary filename.
2. The importer obtains a dataset-level lock/lease before upsert of mappings. `snapshot_lease_ref` is **mandatory for an approved/applying L0 batch** and checked against a still-live private SnapshotLeaseRegistry before any mapping mutation. Once the memory lease expires or app restarts, refuse new mapping writes; reacquire a verified immutable snapshot and a fresh explicit approval before proceeding. `snapshot_lease_ref` is not a permanent recovery credential and is never sent to plugin JS. Future durable leases require a separately reviewed OS-protected snapshot store; do not simply trust saved digests. SQLite UNIQUE constraints are the last safety line; ID allocation and per-content canonical imports are serialized for a dataset, with safe replay of an interrupted approved batch.
3. `legacy_asset_journal` starts at `state='planned'` and `authorization_scope='plan_only'`, using a separately confirmed host gesture tied to the specific local comic evidence, asset SHA-256 and byte length. This row **must never** be interpreted as permission to read an arbitrary source path, stage/promote files, create a `storage_objects` row or write a Content subtree. The restricted L0/L1 planning slice implements only this intent insert. Future staging/apply must require a **new reviewed content+media-root authorization contract**, not widen `plan_only` in place. A planned intent is not a staged asset. Journal intent is durably inserted first. Physical staging/promoting occurs outside canonical SQL transactions. After verify/promote, one SQLite transaction commits a full readable content subtree, complete active order, readable placements, per-record canonical mapping and corresponding committed journal states. No partial active order.
4. Recover `staged`/`verified`/`promoted` artifacts by comparing journal to **both** storage bytes and committed mappings. `promoted` without a canonical reference is an orphan candidate, never automatically user-file deletion. `committed` with missing bytes requires explicit StorageUnavailable error and repair (no silent success).
5. A missing or stale Receipt is derived from durable committed mappings/journal, not counters in memory. The batch can be `partial` without rolling back other fully committed content subtrees. No user-visible “complete” claim while requested categories are deferred/ambiguous.
6. `ReadingSession` can be changed only using `UC-005b` after verified Unit identity and conflict policy; never write a guessed old `ep`/`page` value as unit ID. Old history timestamp is evidence, not fabricated `reading_sessions.updated_at`.
7. `legacy_import_datasets`, mappings, receipts and unresolved evidence are separate from `operation_idempotency` and `import_jobs`. Temporary private snapshots have short retention; mappings/receipts persist under explicit retention and purge choices. No import secrets, direct JS plugins, old Unified Store tables or unsupported source formats.
8. On canonical Content/Collection deletion, application must reconcile mapping FKs/status in the same use-case transaction. `ON DELETE SET NULL` preserves record evidence, **not** license for a subsequent import to recreate deleted data automatically.
9. Source DB integrity is checked on a read-only, SQLite-consistent snapshot. A source `-wal` or `-shm` may be used by SQLite under that input role but is not an independently accepted metadata input. Reject a renamed Unified Store using a validated schema signature.

## diagnostics_events

Bounded local/dev diagnostics evidence (not an unbounded production log store; see `09_OBSERVABILITY.md`).

```sql
CREATE TABLE diagnostics_events (
  id                 TEXT PRIMARY KEY,
  schema_version     TEXT NOT NULL DEFAULT '1.0.0',
  timestamp          TEXT NOT NULL,
  level              TEXT NOT NULL CHECK (level IN ('trace','info','warn','error')),
  channel            TEXT NOT NULL,
  event_name         TEXT NOT NULL,
  correlation_id     TEXT,
  boundary           TEXT,
  action             TEXT,
  authority          TEXT CHECK (authority IN ('canonical_db','storage','source_runtime','unknown')),
  content_id         TEXT REFERENCES contents(id) ON DELETE SET NULL,
  source_platform_id TEXT REFERENCES source_platforms(id) ON DELETE SET NULL,
  payload_json       TEXT NOT NULL    -- sanitized; TIER rules in 06_SECURITY_AUTH_RECOMMENDATION.md
);
CREATE INDEX idx_diag_timestamp   ON diagnostics_events(timestamp);
CREATE INDEX idx_diag_level_ts    ON diagnostics_events(level, timestamp);
CREATE INDEX idx_diag_correlation ON diagnostics_events(correlation_id);
CREATE INDEX idx_diag_event_name  ON diagnostics_events(event_name);
-- Diagnostics writes are BEST-EFFORT: failure to persist diagnostics must never
-- fail or roll back the primary business use case.
```

---

## Transaction Semantics

Atomic operations (all writes succeed or all roll back):

1. **Create Content** — claim/replay idempotency inside the same transaction; INSERT `contents` + `content_metadata` + primary `content_titles` row; `content_metadata.title` must equal the primary title; record completed idempotency result only after canonical writes succeed; no implicit `reading_sessions` row at create time.
2. **Create Section with Units** — INSERT `content_sections` + `content_units`; initial resolved unit order is the canonical source sequence (`unit_index` ASC), via synthetic fallback or explicit `content_unit_orders` materialization.
3. **Update Reading Position** — resolve position to a concrete `unit_id`; upsert the active `reading_sessions` row; if a new active row would coexist with a previous active row, the previous row must transition to a non-active state or the write must fail on the partial unique active index; write scope stays inside the reading-session boundary.
4. **Permanently Delete Content** — explicitly delete or cascade `reading_sessions` before section/unit cascades, or rely on the deferred `NO ACTION` unit FK so validation happens after all cascades; never depend on undefined physical cascade ordering.
5. **Delete Section Node** — caller chooses explicit mode (`delete_subtree` | `reparent_children` | `reject_if_children`); never silently promote children.
6. **Source-link mutations** — recompute `contents.origin_hint` in the same transaction.
7. **Delete ContentUnit referenced as cover** — either keep a valid `cover_storage_object_id` reference or clear both cover refs and set `cover_status = 'none'` in the same transaction.

Concurrency: reader position is last-write-wins in the local single-runtime model. "Serialized per content" is an application requirement, not a backend-portable locking mechanism; any server-backed backend must add an explicit locking/isolation contract (see `00_OVERVIEW.md` persistence boundary) before portable concurrency claims are made.

---

## Legacy guardrails (do NOT use)

The following patterns must not appear in new code:
- `comic_id` column naming → use `content_id`
- `chapter_id` → `section_id`
- `page_id` → `unit_id`
- `comic_source_links` table → `source_links`
- `title_type` column → `title_kind`
- `is_active` / `is_enabled` booleans → use `status` enum
- `page_count` cached field on orders → derive from items
- `order_key` / `order_name` / `normalized_order_name` fields → removed, use `order_type` only
- `sort_order` on items → use `sort_index`
- `is_hidden` on items → removed
- `active_tab_position` on sessions → removed
- `max_page_hint` / `tags_ref` on content_metadata → removed
- `source_platform_aliases` / provider display-name identity matching → removed
- filesystem path columns (`local_path`, `cover_local_path`, `imported_from_path`) → use storage abstraction
- `source_ref_json` as runtime identity → removed
- raw `source_key` as identity → use `canonicalKey` + `remoteWorkId`
- provider-specific taxonomy tables (e.g. `eh_tag_taxonomy`) as core authority → legacy only
