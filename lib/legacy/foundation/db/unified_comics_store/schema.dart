part of '../unified_comics_store.dart';

extension _UnifiedComicsStoreSchema on UnifiedComicsStore {
  Future<void> _ensureVersion1Baseline() async {
    await customStatement('''
      CREATE TABLE IF NOT EXISTS source_platforms (
        id TEXT PRIMARY KEY,
        canonical_key TEXT NOT NULL UNIQUE,
        display_name TEXT NOT NULL,
        kind TEXT NOT NULL CHECK (kind IN ('local', 'remote', 'virtual')),
        is_enabled INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
      );
    ''');
    await customStatement('''
      CREATE TABLE IF NOT EXISTS source_platform_aliases (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        platform_id TEXT NOT NULL,
        alias_key TEXT NOT NULL,
        alias_type TEXT NOT NULL CHECK (
          alias_type IN ('canonical','legacy_key','legacy_type','plugin_key','display_name','migration')
        ),
        legacy_int_type INTEGER,
        source_context TEXT NOT NULL CHECK (
          source_context IN ('global','favorite','history','reader','plugin','download','import')
        ) DEFAULT 'global',
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (platform_id) REFERENCES source_platforms(id) ON DELETE CASCADE,
        UNIQUE(alias_key, alias_type, source_context),
        UNIQUE(legacy_int_type, source_context)
      );
    ''');
    await customStatement('''
      CREATE TABLE IF NOT EXISTS comics (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        normalized_title TEXT NOT NULL,
        cover_local_path TEXT,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
      );
    ''');
    await customStatement('''
      CREATE TABLE IF NOT EXISTS comic_titles (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        comic_id TEXT NOT NULL,
        title TEXT NOT NULL,
        normalized_title TEXT NOT NULL,
        title_type TEXT NOT NULL CHECK (
          title_type IN ('primary','alias','original','translated','romaji','imported_filename','source_title')
        ),
        source_platform_id TEXT,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (comic_id) REFERENCES comics(id) ON DELETE CASCADE,
        FOREIGN KEY (source_platform_id) REFERENCES source_platforms(id) ON DELETE SET NULL,
        UNIQUE(comic_id, normalized_title, title_type, source_platform_id)
      );
    ''');
    await customStatement('''
      CREATE TABLE IF NOT EXISTS local_library_items (
        id TEXT PRIMARY KEY,
        comic_id TEXT NOT NULL,
        storage_type TEXT NOT NULL CHECK (storage_type IN ('downloaded','user_imported','cache')),
        local_root_path TEXT NOT NULL,
        imported_from_path TEXT,
        file_count INTEGER NOT NULL DEFAULT 0,
        total_bytes INTEGER NOT NULL DEFAULT 0,
        content_fingerprint TEXT,
        imported_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (comic_id) REFERENCES comics(id) ON DELETE CASCADE,
        UNIQUE(local_root_path)
      );
    ''');
    await customStatement('''
      CREATE TABLE IF NOT EXISTS comic_source_links (
        id TEXT PRIMARY KEY,
        comic_id TEXT NOT NULL,
        source_platform_id TEXT NOT NULL,
        source_comic_id TEXT NOT NULL,
        link_status TEXT NOT NULL CHECK(link_status IN ('active','candidate','broken')) DEFAULT 'active',
        is_primary INTEGER NOT NULL DEFAULT 0,
        linked_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        metadata_json TEXT,
        FOREIGN KEY (comic_id) REFERENCES comics(id) ON DELETE CASCADE,
        FOREIGN KEY (source_platform_id) REFERENCES source_platforms(id) ON DELETE RESTRICT,
        UNIQUE(comic_id, source_platform_id, source_comic_id)
      );
    ''');
    await customStatement('''
      CREATE TABLE IF NOT EXISTS chapter_source_links (
        id TEXT PRIMARY KEY,
        chapter_id TEXT NOT NULL,
        comic_source_link_id TEXT NOT NULL,
        source_chapter_id TEXT NOT NULL,
        source_url TEXT,
        linked_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        metadata_json TEXT,
        FOREIGN KEY (chapter_id) REFERENCES chapters(id) ON DELETE CASCADE,
        FOREIGN KEY (comic_source_link_id) REFERENCES comic_source_links(id) ON DELETE CASCADE,
        UNIQUE(chapter_id, comic_source_link_id, source_chapter_id)
      );
    ''');
    await customStatement('''
      CREATE TABLE IF NOT EXISTS page_source_links (
        id TEXT PRIMARY KEY,
        page_id TEXT NOT NULL,
        comic_source_link_id TEXT NOT NULL,
        chapter_source_link_id TEXT,
        source_page_id TEXT NOT NULL,
        source_url TEXT,
        linked_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        metadata_json TEXT,
        FOREIGN KEY (page_id) REFERENCES pages(id) ON DELETE CASCADE,
        FOREIGN KEY (comic_source_link_id) REFERENCES comic_source_links(id) ON DELETE CASCADE,
        FOREIGN KEY (chapter_source_link_id) REFERENCES chapter_source_links(id) ON DELETE SET NULL,
        UNIQUE(page_id, comic_source_link_id, source_page_id)
      );
    ''');
    await customStatement('''
      CREATE TABLE IF NOT EXISTS chapters (
        id TEXT PRIMARY KEY,
        comic_id TEXT NOT NULL,
        chapter_no REAL,
        title TEXT NOT NULL,
        normalized_title TEXT NOT NULL,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (comic_id) REFERENCES comics(id) ON DELETE CASCADE,
        UNIQUE(comic_id, chapter_no),
        UNIQUE(comic_id, normalized_title)
      );
    ''');
    await customStatement('''
      CREATE TABLE IF NOT EXISTS pages (
        id TEXT PRIMARY KEY,
        chapter_id TEXT NOT NULL,
        page_index INTEGER NOT NULL,
        local_path TEXT,
        content_hash TEXT,
        width INTEGER,
        height INTEGER,
        bytes INTEGER,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (chapter_id) REFERENCES chapters(id) ON DELETE CASCADE,
        UNIQUE(chapter_id, page_index)
      );
    ''');
    await customStatement('''
      CREATE TABLE IF NOT EXISTS page_orders (
        id TEXT PRIMARY KEY,
        chapter_id TEXT NOT NULL,
        order_name TEXT NOT NULL,
        normalized_order_name TEXT NOT NULL,
        order_type TEXT NOT NULL CHECK (order_type IN ('source_default','user_custom','imported_folder','temporary_session')),
        is_active INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (chapter_id) REFERENCES chapters(id) ON DELETE CASCADE,
        UNIQUE(chapter_id, normalized_order_name)
      );
    ''');
    await customStatement('''
      CREATE TABLE IF NOT EXISTS page_order_items (
        page_order_id TEXT NOT NULL,
        page_id TEXT NOT NULL,
        sort_order INTEGER NOT NULL,
        is_hidden INTEGER NOT NULL DEFAULT 0,
        added_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (page_order_id, page_id),
        FOREIGN KEY (page_order_id) REFERENCES page_orders(id) ON DELETE CASCADE,
        FOREIGN KEY (page_id) REFERENCES pages(id) ON DELETE CASCADE,
        UNIQUE(page_order_id, sort_order)
      );
    ''');
    await _createIndexesForV1();
  }

  Future<void> _ensureV2Schema() async {
    await customStatement('''
      CREATE TABLE IF NOT EXISTS source_tags (
        id TEXT PRIMARY KEY,
        source_platform_id TEXT NOT NULL,
        namespace TEXT NOT NULL,
        tag_key TEXT NOT NULL,
        display_name TEXT NOT NULL,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (source_platform_id) REFERENCES source_platforms(id) ON DELETE CASCADE,
        UNIQUE(source_platform_id, namespace, tag_key)
      );
    ''');
    await customStatement('''
      CREATE TABLE IF NOT EXISTS comic_source_link_tags (
        comic_source_link_id TEXT NOT NULL,
        source_tag_id TEXT NOT NULL,
        added_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (comic_source_link_id, source_tag_id),
        FOREIGN KEY (comic_source_link_id) REFERENCES comic_source_links(id) ON DELETE CASCADE,
        FOREIGN KEY (source_tag_id) REFERENCES source_tags(id) ON DELETE CASCADE
      );
    ''');
    await customStatement('''
      CREATE TABLE IF NOT EXISTS user_tags (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        normalized_name TEXT NOT NULL UNIQUE,
        color TEXT,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
      );
    ''');
    await customStatement('''
      CREATE TABLE IF NOT EXISTS comic_user_tags (
        comic_id TEXT NOT NULL,
        user_tag_id TEXT NOT NULL,
        added_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (comic_id, user_tag_id),
        FOREIGN KEY (comic_id) REFERENCES comics(id) ON DELETE CASCADE,
        FOREIGN KEY (user_tag_id) REFERENCES user_tags(id) ON DELETE CASCADE
      );
    ''');
    await customStatement('''
      CREATE TABLE IF NOT EXISTS eh_tag_taxonomy (
        provider_key TEXT NOT NULL,
        locale TEXT NOT NULL,
        namespace TEXT NOT NULL,
        tag_key TEXT NOT NULL,
        translated_label TEXT NOT NULL,
        source_sha TEXT,
        source_version INTEGER,
        updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (provider_key, locale, namespace, tag_key)
      );
    ''');
    await customStatement('''
      CREATE TABLE IF NOT EXISTS favorites (
        comic_id TEXT PRIMARY KEY,
        source_key TEXT NOT NULL,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (comic_id) REFERENCES comics(id) ON DELETE CASCADE
      );
    ''');
    await customStatement('''
      CREATE TABLE IF NOT EXISTS favorite_folders (
        folder_name TEXT PRIMARY KEY,
        order_value INTEGER NOT NULL DEFAULT 0,
        source_key TEXT,
        source_folder TEXT,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
      );
    ''');
    await customStatement('''
      CREATE TABLE IF NOT EXISTS favorite_folder_items (
        folder_name TEXT NOT NULL,
        comic_id TEXT NOT NULL,
        display_order INTEGER NOT NULL DEFAULT 0,
        added_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (folder_name, comic_id),
        FOREIGN KEY (folder_name) REFERENCES favorite_folders(folder_name) ON DELETE CASCADE
      );
    ''');
    await customStatement('''
      CREATE TABLE IF NOT EXISTS history_events (
        id TEXT PRIMARY KEY,
        comic_id TEXT NOT NULL,
        source_type_value INTEGER NOT NULL,
        source_key TEXT NOT NULL,
        title TEXT NOT NULL,
        subtitle TEXT NOT NULL,
        cover TEXT NOT NULL,
        event_time TEXT NOT NULL,
        chapter_index INTEGER NOT NULL,
        page_index INTEGER NOT NULL,
        chapter_group INTEGER,
        read_episode TEXT NOT NULL,
        max_page INTEGER,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (comic_id) REFERENCES comics(id) ON DELETE CASCADE
      );
    ''');
    await _ensureTextColumn('comic_source_links', 'source_url');
    await _ensureTextColumn('comic_source_links', 'source_title');
    await _ensureTextColumn('comic_source_links', 'downloaded_at');
    await _ensureTextColumn('comic_source_links', 'last_verified_at');
    await _createIndexesForV2();
  }

  Future<void> _ensureV3Schema() async {
    await customStatement('''
      CREATE TABLE IF NOT EXISTS reader_sessions (
        id TEXT PRIMARY KEY,
        comic_id TEXT NOT NULL,
        active_tab_id TEXT,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (comic_id) REFERENCES comics(id) ON DELETE CASCADE,
        FOREIGN KEY (active_tab_id) REFERENCES reader_tabs(id) ON DELETE SET NULL
      );
    ''');
    await customStatement('''
      CREATE TABLE IF NOT EXISTS reader_tabs (
        id TEXT PRIMARY KEY,
        session_id TEXT NOT NULL,
        comic_id TEXT NOT NULL,
        chapter_id TEXT NOT NULL,
        page_index INTEGER NOT NULL,
        source_ref_json TEXT NOT NULL,
        page_order_id TEXT,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (session_id) REFERENCES reader_sessions(id) ON DELETE CASCADE,
        FOREIGN KEY (comic_id) REFERENCES comics(id) ON DELETE CASCADE,
        UNIQUE(session_id, chapter_id, source_ref_json)
      );
    ''');
    await customStatement('''
      CREATE TABLE IF NOT EXISTS remote_match_candidates (
        id TEXT PRIMARY KEY,
        comic_id TEXT NOT NULL,
        source_platform_id TEXT NOT NULL,
        source_comic_id TEXT NOT NULL,
        source_url TEXT NOT NULL,
        source_title TEXT NOT NULL,
        confidence REAL NOT NULL,
        metadata_json TEXT NOT NULL,
        status TEXT NOT NULL CHECK (status IN ('pending', 'accepted', 'rejected')),
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (comic_id) REFERENCES comics(id) ON DELETE CASCADE,
        FOREIGN KEY (source_platform_id) REFERENCES source_platforms(id) ON DELETE RESTRICT,
        UNIQUE(comic_id, source_platform_id, source_comic_id)
      );
    ''');
    await _createIndexesForV3();
  }

  Future<void> _ensureV4Schema() async {
    await customStatement('''
      CREATE TABLE IF NOT EXISTS cache_entries (
        cache_key TEXT PRIMARY KEY NOT NULL,
        namespace TEXT NOT NULL,
        source_platform_id TEXT,
        owner_ref TEXT,
        remote_url_hash TEXT,
        storage_dir TEXT NOT NULL,
        file_name TEXT NOT NULL,
        expires_at_ms INTEGER NOT NULL,
        content_type TEXT,
        size_bytes INTEGER,
        created_at_ms INTEGER NOT NULL,
        last_accessed_at_ms INTEGER
      );
    ''');
    await _createIndexesForV4();
  }

  Future<void> _ensureV5Schema() async {
    await customStatement('''
      CREATE TABLE IF NOT EXISTS app_settings (
        key TEXT PRIMARY KEY,
        value_json TEXT NOT NULL,
        value_type TEXT NOT NULL,
        sync_policy TEXT NOT NULL,
        updated_at_ms INTEGER NOT NULL
      );
    ''');
    await customStatement('''
      CREATE TABLE IF NOT EXISTS search_history (
        keyword TEXT PRIMARY KEY,
        position INTEGER NOT NULL,
        updated_at_ms INTEGER NOT NULL
      );
    ''');
    await customStatement('''
      CREATE TABLE IF NOT EXISTS implicit_data (
        key TEXT PRIMARY KEY,
        value_json TEXT NOT NULL,
        updated_at_ms INTEGER NOT NULL
      );
    ''');
    await _createIndexesForV5();
  }

  Future<void> _ensureV6Schema() async {
    await customStatement('''
      CREATE TABLE IF NOT EXISTS source_repositories (
        id TEXT PRIMARY KEY NOT NULL,
        name TEXT NOT NULL,
        index_url TEXT NOT NULL,
        enabled INTEGER NOT NULL DEFAULT 1 CHECK (enabled IN (0, 1)),
        user_added INTEGER NOT NULL DEFAULT 1 CHECK (user_added IN (0, 1)),
        trust_level TEXT NOT NULL DEFAULT 'user' CHECK (trust_level IN ('official', 'user', 'unknown')),
        last_refresh_at_ms INTEGER,
        last_refresh_status TEXT CHECK (last_refresh_status IS NULL OR last_refresh_status IN ('success', 'failed', 'never')),
        last_error_code TEXT,
        created_at_ms INTEGER NOT NULL,
        updated_at_ms INTEGER NOT NULL
      );
    ''');
    await customStatement('''
      CREATE TABLE IF NOT EXISTS source_packages (
        source_key TEXT NOT NULL,
        repository_id TEXT NOT NULL,
        name TEXT NOT NULL,
        file_name TEXT,
        script_url TEXT,
        available_version TEXT,
        description TEXT,
        content_hash TEXT,
        last_seen_at_ms INTEGER NOT NULL,
        PRIMARY KEY (source_key, repository_id),
        FOREIGN KEY (repository_id) REFERENCES source_repositories(id) ON DELETE CASCADE
      );
    ''');
    await _createIndexesForV6();
  }

  Future<void> _createIndexesForV1() async {
    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_comics_normalized_title
      ON comics(normalized_title);
    ''');
    await customStatement('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_comic_source_links_one_primary_per_comic
      ON comic_source_links(comic_id)
      WHERE is_primary = 1;
    ''');
    await customStatement('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_page_orders_one_active_per_chapter
      ON page_orders(chapter_id)
      WHERE is_active = 1;
    ''');
  }

  Future<void> _createIndexesForV2() async {
    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_eh_tag_taxonomy_lookup
      ON eh_tag_taxonomy(provider_key, locale, namespace, tag_key);
    ''');
    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_local_library_items_storage_updated
      ON local_library_items(storage_type, updated_at DESC);
    ''');
    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_favorites_source_key
      ON favorites(source_key, created_at DESC);
    ''');
    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_favorite_folders_order
      ON favorite_folders(order_value ASC, folder_name ASC);
    ''');
    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_favorite_folder_items_folder_order
      ON favorite_folder_items(folder_name, display_order ASC, added_at ASC);
    ''');
    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_history_events_comic_time
      ON history_events(comic_id, event_time DESC);
    ''');
  }

  Future<void> _createIndexesForV3() async {
    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_reader_sessions_comic_updated
      ON reader_sessions(comic_id, updated_at DESC, created_at DESC, id ASC);
    ''');
    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_reader_tabs_session_updated
      ON reader_tabs(session_id, updated_at DESC, created_at DESC, id ASC);
    ''');
    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_remote_match_candidates_comic_updated
      ON remote_match_candidates(comic_id, updated_at DESC, created_at DESC, id ASC);
    ''');
  }

  Future<void> _createIndexesForV4() async {
    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_cache_entries_expiry
      ON cache_entries(expires_at_ms ASC, cache_key ASC);
    ''');
  }

  Future<void> _createIndexesForV5() async {
    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_search_history_position
      ON search_history(position ASC, updated_at_ms DESC);
    ''');
  }

  Future<void> _createIndexesForV6() async {
    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_source_repositories_enabled_updated
      ON source_repositories(enabled ASC, updated_at_ms DESC, id ASC);
    ''');
    await customStatement('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_source_repositories_index_url
      ON source_repositories(index_url);
    ''');
    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_source_packages_repository_key
      ON source_packages(repository_id, source_key);
    ''');
  }
}
