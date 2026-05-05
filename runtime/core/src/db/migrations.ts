import { sql, type Kysely } from "kysely";

import type { CoreDatabaseSchema } from "./schema.js";

async function ensureNoDanglingForeignKeys(
  db: Kysely<CoreDatabaseSchema>,
): Promise<void> {
  const results = await sql<{ table: string; rowid: number; parent: string; fkid: number }>`
    PRAGMA foreign_key_check
  `.execute(db);

  if (results.rows.length > 0) {
    const details = results.rows
      .map((row) => `${row.table}:${row.rowid}->${row.parent}#${row.fkid}`)
      .join(", ");
    throw new Error(`Foreign key check failed: ${details}`);
  }
}

export async function migrateCoreDatabase(
  db: Kysely<CoreDatabaseSchema>,
): Promise<void> {
  await sql`
    CREATE TABLE IF NOT EXISTS comics (
      id TEXT PRIMARY KEY,
      normalized_title TEXT NOT NULL UNIQUE,
      origin_hint TEXT NOT NULL DEFAULT 'unknown'
        CHECK (origin_hint IN ('unknown', 'local', 'remote', 'mixed')),
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  `.execute(db);

  await sql`
    CREATE TABLE IF NOT EXISTS source_platforms (
      id TEXT PRIMARY KEY,
      canonical_key TEXT NOT NULL UNIQUE,
      display_name TEXT NOT NULL,
      kind TEXT NOT NULL CHECK (kind IN ('local', 'remote', 'virtual')),
      is_enabled INTEGER NOT NULL CHECK (is_enabled IN (0, 1)),
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  `.execute(db);

  await sql`
    CREATE TABLE IF NOT EXISTS storage_backends (
      id TEXT PRIMARY KEY,
      backend_key TEXT NOT NULL UNIQUE,
      display_name TEXT NOT NULL,
      backend_kind TEXT NOT NULL CHECK (backend_kind IN ('local_app_data', 'webdav', 'future')),
      config_json TEXT NOT NULL,
      secret_ref TEXT,
      is_enabled INTEGER NOT NULL CHECK (is_enabled IN (0, 1)),
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  `.execute(db);

  await sql`
    CREATE TABLE IF NOT EXISTS storage_objects (
      id TEXT PRIMARY KEY,
      object_kind TEXT NOT NULL CHECK (object_kind IN ('page_image', 'cover', 'archive', 'backup', 'cache')),
      content_hash TEXT,
      size_bytes INTEGER,
      mime_type TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  `.execute(db);

  await sql`
    CREATE TABLE IF NOT EXISTS chapters (
      id TEXT PRIMARY KEY,
      comic_id TEXT NOT NULL REFERENCES comics(id) ON DELETE CASCADE,
      parent_chapter_id TEXT REFERENCES chapters(id) ON DELETE SET NULL,
      chapter_kind TEXT NOT NULL CHECK (chapter_kind IN ('season', 'volume', 'chapter', 'episode', 'oneshot', 'group')),
      chapter_number REAL NOT NULL,
      title TEXT,
      display_label TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      UNIQUE (comic_id, parent_chapter_id, chapter_number)
    )
  `.execute(db);

  await sql`
    CREATE INDEX IF NOT EXISTS idx_chapters_comic_id
      ON chapters(comic_id)
  `.execute(db);

  await sql`
    CREATE INDEX IF NOT EXISTS idx_chapters_parent_chapter_id
      ON chapters(parent_chapter_id)
  `.execute(db);

  await sql`
    CREATE TABLE IF NOT EXISTS source_links (
      id TEXT PRIMARY KEY,
      comic_id TEXT NOT NULL REFERENCES comics(id) ON DELETE CASCADE,
      source_platform_id TEXT NOT NULL REFERENCES source_platforms(id) ON DELETE RESTRICT,
      remote_work_id TEXT NOT NULL,
      remote_url TEXT,
      display_title TEXT,
      link_status TEXT NOT NULL CHECK (link_status IN ('active', 'candidate', 'rejected', 'stale')),
      confidence TEXT NOT NULL CHECK (confidence IN ('manual', 'auto_high', 'auto_low')),
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      UNIQUE (source_platform_id, remote_work_id)
    )
  `.execute(db);

  await sql`
    CREATE INDEX IF NOT EXISTS idx_source_links_comic_id
      ON source_links(comic_id)
  `.execute(db);

  await sql`
    CREATE TABLE IF NOT EXISTS chapter_source_links (
      id TEXT PRIMARY KEY,
      chapter_id TEXT NOT NULL REFERENCES chapters(id) ON DELETE CASCADE,
      source_link_id TEXT NOT NULL REFERENCES source_links(id) ON DELETE CASCADE,
      remote_chapter_id TEXT NOT NULL,
      remote_url TEXT,
      remote_label TEXT,
      link_status TEXT NOT NULL CHECK (link_status IN ('active', 'candidate', 'rejected', 'stale')),
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      UNIQUE (source_link_id, remote_chapter_id)
    )
  `.execute(db);

  await sql`
    CREATE TABLE IF NOT EXISTS pages (
      id TEXT PRIMARY KEY,
      chapter_id TEXT NOT NULL REFERENCES chapters(id) ON DELETE CASCADE,
      page_index INTEGER NOT NULL,
      storage_object_id TEXT REFERENCES storage_objects(id) ON DELETE SET NULL,
      chapter_source_link_id TEXT REFERENCES chapter_source_links(id) ON DELETE SET NULL,
      mime_type TEXT,
      width INTEGER,
      height INTEGER,
      checksum TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      UNIQUE (chapter_id, page_index)
    )
  `.execute(db);

  await sql`
    CREATE INDEX IF NOT EXISTS idx_pages_storage_object_id
      ON pages(storage_object_id)
  `.execute(db);

  await sql`
    CREATE INDEX IF NOT EXISTS idx_pages_chapter_source_link_id
      ON pages(chapter_source_link_id)
  `.execute(db);

  await sql`
    CREATE TABLE IF NOT EXISTS comic_metadata (
      comic_id TEXT PRIMARY KEY REFERENCES comics(id) ON DELETE CASCADE,
      title TEXT NOT NULL,
      description TEXT,
      cover_page_id TEXT REFERENCES pages(id) ON DELETE SET NULL,
      cover_storage_object_id TEXT REFERENCES storage_objects(id) ON DELETE SET NULL,
      author_name TEXT,
      metadata_json TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  `.execute(db);

  await sql`
    CREATE TABLE IF NOT EXISTS comic_titles (
      id TEXT PRIMARY KEY,
      comic_id TEXT NOT NULL REFERENCES comics(id) ON DELETE CASCADE,
      title TEXT NOT NULL,
      normalized_title TEXT NOT NULL,
      locale TEXT,
      source_platform_id TEXT REFERENCES source_platforms(id) ON DELETE SET NULL,
      source_link_id TEXT REFERENCES source_links(id) ON DELETE SET NULL,
      title_kind TEXT NOT NULL CHECK (title_kind IN ('primary', 'alias', 'translated', 'source')),
      created_at TEXT NOT NULL,
      UNIQUE (comic_id, normalized_title, locale, source_platform_id)
    )
  `.execute(db);

  await sql`
    CREATE INDEX IF NOT EXISTS idx_comic_titles_comic_id
      ON comic_titles(comic_id)
  `.execute(db);

  await sql`
    CREATE INDEX IF NOT EXISTS idx_comic_titles_normalized_title
      ON comic_titles(normalized_title)
  `.execute(db);

  await sql`
    CREATE UNIQUE INDEX IF NOT EXISTS ux_comic_titles_one_primary
      ON comic_titles(comic_id)
      WHERE title_kind = 'primary'
  `.execute(db);

  await sql`
    CREATE UNIQUE INDEX IF NOT EXISTS ux_comic_titles_source_less_normalized
      ON comic_titles(comic_id, normalized_title)
      WHERE locale IS NULL AND source_platform_id IS NULL
  `.execute(db);

  await sql`
    CREATE TABLE IF NOT EXISTS page_orders (
      id TEXT PRIMARY KEY,
      chapter_id TEXT NOT NULL REFERENCES chapters(id) ON DELETE CASCADE,
      order_key TEXT NOT NULL CHECK (order_key IN ('source', 'user', 'import_detected', 'custom')),
      order_type TEXT NOT NULL CHECK (order_type IN ('source', 'user_override', 'import_detected', 'custom')),
      is_active INTEGER NOT NULL CHECK (is_active IN (0, 1)),
      page_count INTEGER NOT NULL,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  `.execute(db);

  await sql`
    CREATE UNIQUE INDEX IF NOT EXISTS ux_page_orders_active_per_chapter
      ON page_orders(chapter_id)
      WHERE is_active = 1
  `.execute(db);

  await sql`
    CREATE TABLE IF NOT EXISTS page_order_items (
      id TEXT PRIMARY KEY,
      page_order_id TEXT NOT NULL REFERENCES page_orders(id) ON DELETE CASCADE,
      page_id TEXT NOT NULL REFERENCES pages(id) ON DELETE CASCADE,
      sort_index INTEGER NOT NULL,
      created_at TEXT NOT NULL,
      UNIQUE (page_order_id, sort_index),
      UNIQUE (page_order_id, page_id)
    )
  `.execute(db);

  await sql`
    CREATE TABLE IF NOT EXISTS storage_placements (
      id TEXT PRIMARY KEY,
      storage_object_id TEXT NOT NULL REFERENCES storage_objects(id) ON DELETE CASCADE,
      storage_backend_id TEXT NOT NULL REFERENCES storage_backends(id) ON DELETE RESTRICT,
      object_key TEXT NOT NULL,
      role TEXT NOT NULL CHECK (role IN ('authority', 'cache', 'mirror', 'staging')),
      sync_status TEXT NOT NULL CHECK (sync_status IN ('pending', 'uploading', 'synced', 'failed', 'evicted')),
      last_verified_at TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  `.execute(db);

  await sql`
    CREATE TABLE IF NOT EXISTS reader_sessions (
      id TEXT PRIMARY KEY,
      comic_id TEXT NOT NULL UNIQUE REFERENCES comics(id) ON DELETE CASCADE,
      chapter_id TEXT NOT NULL REFERENCES chapters(id) ON DELETE CASCADE,
      page_id TEXT REFERENCES pages(id) ON DELETE SET NULL,
      page_index INTEGER NOT NULL,
      source_link_id TEXT REFERENCES source_links(id) ON DELETE SET NULL,
      chapter_source_link_id TEXT REFERENCES chapter_source_links(id) ON DELETE SET NULL,
      reader_mode TEXT NOT NULL CHECK (reader_mode IN ('gallery', 'continuous')),
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  `.execute(db);

  await sql`
    CREATE TABLE IF NOT EXISTS diagnostics_events (
      id TEXT PRIMARY KEY,
      timestamp TEXT NOT NULL,
      level TEXT NOT NULL CHECK (level IN ('trace', 'info', 'warn', 'error')),
      channel TEXT NOT NULL,
      event_name TEXT NOT NULL,
      correlation_id TEXT,
      boundary TEXT,
      action TEXT,
      authority TEXT CHECK (authority IN ('canonical_db', 'storage', 'source_runtime', 'unknown')),
      comic_id TEXT REFERENCES comics(id) ON DELETE SET NULL,
      source_platform_id TEXT REFERENCES source_platforms(id) ON DELETE SET NULL,
      payload_json TEXT NOT NULL
    )
  `.execute(db);

  await ensureNoDanglingForeignKeys(db);
}
