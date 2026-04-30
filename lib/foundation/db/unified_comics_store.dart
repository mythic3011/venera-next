import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/common.dart' as sqlite_common;
import 'package:venera/foundation/source_identity/source_identity.dart';

const String sourceContextGlobal = 'global';
const String canonicalDomainDatabaseDirectoryName = 'data';
const String canonicalDomainDatabaseFileName = 'venera.db';

String canonicalDomainDatabasePath(String rootPath) {
  return p.join(
    rootPath,
    canonicalDomainDatabaseDirectoryName,
    canonicalDomainDatabaseFileName,
  );
}

class SourcePlatformRecord {
  const SourcePlatformRecord({
    required this.id,
    required this.canonicalKey,
    required this.displayName,
    required this.kind,
    this.isEnabled = true,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String canonicalKey;
  final String displayName;
  final String kind;
  final bool isEnabled;
  final String? createdAt;
  final String? updatedAt;
}

class SourcePlatformAliasRecord {
  const SourcePlatformAliasRecord({
    this.id,
    required this.platformId,
    required this.aliasKey,
    required this.aliasType,
    this.legacyIntType,
    this.sourceContext = sourceContextGlobal,
    this.createdAt,
  });

  final int? id;
  final String platformId;
  final String aliasKey;
  final String aliasType;
  final int? legacyIntType;
  final String sourceContext;
  final String? createdAt;
}

class ComicRecord {
  const ComicRecord({
    required this.id,
    required this.title,
    required this.normalizedTitle,
    this.coverLocalPath,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String title;
  final String normalizedTitle;
  final String? coverLocalPath;
  final String? createdAt;
  final String? updatedAt;
}

class ComicTitleRecord {
  const ComicTitleRecord({
    this.id,
    required this.comicId,
    required this.title,
    required this.normalizedTitle,
    required this.titleType,
    this.sourcePlatformId,
    this.createdAt,
  });

  final int? id;
  final String comicId;
  final String title;
  final String normalizedTitle;
  final String titleType;
  final String? sourcePlatformId;
  final String? createdAt;
}

class LocalLibraryItemRecord {
  const LocalLibraryItemRecord({
    required this.id,
    required this.comicId,
    required this.storageType,
    required this.localRootPath,
    this.importedFromPath,
    this.fileCount = 0,
    this.totalBytes = 0,
    this.contentFingerprint,
    this.importedAt,
    this.updatedAt,
  });

  final String id;
  final String comicId;
  final String storageType;
  final String localRootPath;
  final String? importedFromPath;
  final int fileCount;
  final int totalBytes;
  final String? contentFingerprint;
  final String? importedAt;
  final String? updatedAt;
}

class FavoriteRecord {
  const FavoriteRecord({
    required this.comicId,
    required this.sourceKey,
    this.createdAt,
  });

  final String comicId;
  final String sourceKey;
  final String? createdAt;
}

class ChapterRecord {
  const ChapterRecord({
    required this.id,
    required this.comicId,
    this.chapterNo,
    required this.title,
    required this.normalizedTitle,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String comicId;
  final double? chapterNo;
  final String title;
  final String normalizedTitle;
  final String? createdAt;
  final String? updatedAt;
}

class PageRecord {
  const PageRecord({
    required this.id,
    required this.chapterId,
    required this.pageIndex,
    required this.localPath,
    this.contentHash,
    this.width,
    this.height,
    this.bytes,
    this.createdAt,
  });

  final String id;
  final String chapterId;
  final int pageIndex;
  final String localPath;
  final String? contentHash;
  final int? width;
  final int? height;
  final int? bytes;
  final String? createdAt;
}

class PageOrderRecord {
  const PageOrderRecord({
    required this.id,
    required this.chapterId,
    required this.orderName,
    required this.normalizedOrderName,
    required this.orderType,
    this.isActive = false,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String chapterId;
  final String orderName;
  final String normalizedOrderName;
  final String orderType;
  final bool isActive;
  final String? createdAt;
  final String? updatedAt;
}

class PageOrderItemRecord {
  const PageOrderItemRecord({
    required this.pageOrderId,
    required this.pageId,
    required this.sortOrder,
    this.isHidden = false,
    this.addedAt,
  });

  final String pageOrderId;
  final String pageId;
  final int sortOrder;
  final bool isHidden;
  final String? addedAt;
}

class PageOrderSummaryRecord {
  const PageOrderSummaryRecord({
    required this.totalOrders,
    required this.totalPageCount,
    required this.visiblePageCount,
    this.activeOrderId,
    this.activeOrderType,
  });

  final String? activeOrderId;
  final String? activeOrderType;
  final int totalOrders;
  final int totalPageCount;
  final int visiblePageCount;
}

class HistoryEventRecord {
  const HistoryEventRecord({
    required this.id,
    required this.comicId,
    required this.sourceTypeValue,
    required this.sourceKey,
    required this.title,
    required this.subtitle,
    required this.cover,
    required this.eventTime,
    required this.chapterIndex,
    required this.pageIndex,
    required this.readEpisode,
    this.chapterGroup,
    this.maxPage,
    this.createdAt,
  });

  final String id;
  final String comicId;
  final int sourceTypeValue;
  final String sourceKey;
  final String title;
  final String subtitle;
  final String cover;
  final String eventTime;
  final int chapterIndex;
  final int pageIndex;
  final String readEpisode;
  final int? chapterGroup;
  final int? maxPage;
  final String? createdAt;
}

class ResolvedSourcePlatform {
  const ResolvedSourcePlatform({
    required this.platformId,
    required this.canonicalKey,
    required this.displayName,
    required this.kind,
    required this.matchedAlias,
    required this.matchedAliasType,
    required this.sourceContext,
    this.legacyIntType,
  });

  final String platformId;
  final String canonicalKey;
  final String displayName;
  final String kind;
  final String matchedAlias;
  final String matchedAliasType;
  final String sourceContext;
  final int? legacyIntType;
}

class UnifiedComicSnapshot {
  const UnifiedComicSnapshot({
    required this.comic,
    required this.titles,
    required this.localLibraryItems,
    this.favorite,
    this.chapters = const <ChapterRecord>[],
  });

  final ComicRecord comic;
  final List<ComicTitleRecord> titles;
  final List<LocalLibraryItemRecord> localLibraryItems;
  final FavoriteRecord? favorite;
  final List<ChapterRecord> chapters;
}

class UnifiedComicsStore extends GeneratedDatabase {
  UnifiedComicsStore(this.dbPath)
    : super(
        NativeDatabase.createInBackground(
          _prepareDatabaseFile(dbPath),
          setup: _configureDatabase,
        ),
      );

  final String dbPath;

  UnifiedComicsStore.atCanonicalPath(String rootPath)
    : this(canonicalDomainDatabasePath(rootPath));

  static File _prepareDatabaseFile(String dbPath) {
    final file = File(dbPath);
    file.parent.createSync(recursive: true);
    return file;
  }

  static void _configureDatabase(sqlite_common.CommonDatabase database) {
    database.execute('PRAGMA foreign_keys = ON;');
    database.execute('PRAGMA journal_mode = WAL;');
  }

  @override
  Iterable<TableInfo<Table, Object?>> get allTables => const [];

  @override
  int get schemaVersion => 1;

  Future<void> init() async {
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
          alias_type IN (
            'canonical',
            'legacy_key',
            'legacy_type',
            'plugin_key',
            'display_name',
            'migration'
          )
        ),
        legacy_int_type INTEGER,
        source_context TEXT NOT NULL CHECK (
          source_context IN (
            'global',
            'favorite',
            'history',
            'reader',
            'plugin',
            'download',
            'import'
          )
        ) DEFAULT 'global',
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (platform_id)
          REFERENCES source_platforms(id)
          ON DELETE CASCADE,
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
      CREATE INDEX IF NOT EXISTS idx_comics_normalized_title
      ON comics(normalized_title);
    ''');
    await customStatement('''
      CREATE TABLE IF NOT EXISTS comic_titles (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        comic_id TEXT NOT NULL,
        title TEXT NOT NULL,
        normalized_title TEXT NOT NULL,
        title_type TEXT NOT NULL CHECK (
          title_type IN (
            'primary',
            'alias',
            'original',
            'translated',
            'romaji',
            'imported_filename',
            'source_title'
          )
        ),
        source_platform_id TEXT,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (comic_id)
          REFERENCES comics(id)
          ON DELETE CASCADE,
        FOREIGN KEY (source_platform_id)
          REFERENCES source_platforms(id)
          ON DELETE SET NULL,
        UNIQUE(comic_id, normalized_title, title_type, source_platform_id)
      );
    ''');
    await customStatement('''
      CREATE TABLE IF NOT EXISTS local_library_items (
        id TEXT PRIMARY KEY,
        comic_id TEXT NOT NULL,
        storage_type TEXT NOT NULL CHECK (
          storage_type IN (
            'downloaded',
            'user_imported',
            'cache'
          )
        ),
        local_root_path TEXT NOT NULL,
        imported_from_path TEXT,
        file_count INTEGER NOT NULL DEFAULT 0,
        total_bytes INTEGER NOT NULL DEFAULT 0,
        content_fingerprint TEXT,
        imported_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (comic_id)
          REFERENCES comics(id)
          ON DELETE CASCADE,
        UNIQUE(local_root_path)
      );
    ''');
    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_local_library_items_storage_updated
      ON local_library_items(storage_type, updated_at DESC);
    ''');
    await customStatement('''
      CREATE TABLE IF NOT EXISTS favorites (
        comic_id TEXT PRIMARY KEY,
        source_key TEXT NOT NULL,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (comic_id)
          REFERENCES comics(id)
          ON DELETE CASCADE
      );
    ''');
    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_favorites_source_key
      ON favorites(source_key, created_at DESC);
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
        FOREIGN KEY (comic_id)
          REFERENCES comics(id)
          ON DELETE CASCADE,
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
        FOREIGN KEY (chapter_id)
          REFERENCES chapters(id)
          ON DELETE CASCADE,
        UNIQUE(chapter_id, page_index)
      );
    ''');
    await customStatement('''
      CREATE TABLE IF NOT EXISTS page_orders (
        id TEXT PRIMARY KEY,
        chapter_id TEXT NOT NULL,
        order_name TEXT NOT NULL,
        normalized_order_name TEXT NOT NULL,
        order_type TEXT NOT NULL CHECK (
          order_type IN (
            'source_default',
            'user_custom',
            'imported_folder',
            'temporary_session'
          )
        ),
        is_active INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (chapter_id)
          REFERENCES chapters(id)
          ON DELETE CASCADE,
        UNIQUE(chapter_id, normalized_order_name)
      );
    ''');
    await customStatement('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_page_orders_one_active_per_chapter
      ON page_orders(chapter_id)
      WHERE is_active = 1;
    ''');
    await customStatement('''
      CREATE TABLE IF NOT EXISTS page_order_items (
        page_order_id TEXT NOT NULL,
        page_id TEXT NOT NULL,
        sort_order INTEGER NOT NULL,
        is_hidden INTEGER NOT NULL DEFAULT 0,
        added_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (page_order_id, page_id),
        FOREIGN KEY (page_order_id)
          REFERENCES page_orders(id)
          ON DELETE CASCADE,
        FOREIGN KEY (page_id)
          REFERENCES pages(id)
          ON DELETE CASCADE,
        UNIQUE(page_order_id, sort_order)
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
        FOREIGN KEY (comic_id)
          REFERENCES comics(id)
          ON DELETE CASCADE
      );
    ''');
    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_history_events_comic_time
      ON history_events(comic_id, event_time DESC);
    ''');
  }

  Future<List<String>> listTables() async {
    final rows = await customSelect(
      "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name;",
    ).get();
    return rows.map((row) => row.read<String>('name')).toList();
  }

  Future<String> currentJournalMode() async {
    final rows = await customSelect('PRAGMA journal_mode;').get();
    return rows.single.data.values.single.toString().toLowerCase();
  }

  Future<int> foreignKeysEnabled() async {
    final rows = await customSelect('PRAGMA foreign_keys;').get();
    return int.parse(rows.single.data.values.single.toString());
  }

  Future<void> seedDefaultSourcePlatforms() async {
    final platforms = sourcePlatformResolver.platforms
        .map(
          (platform) => SourcePlatformRecord(
            id: platform.platformId,
            canonicalKey: platform.canonicalKey,
            displayName: platform.displayName,
            kind: platform.kind,
          ),
        )
        .toList(growable: false);
    final aliases = sourcePlatformResolver.platforms
        .expand(_aliasesForDefinition)
        .toList(growable: false);
    await transaction(() async {
      for (final platform in platforms) {
        await upsertSourcePlatform(platform);
      }
      for (final alias in aliases) {
        await upsertSourcePlatformAlias(alias);
      }
    });
  }

  Future<void> upsertSourcePlatform(SourcePlatformRecord record) {
    return customStatement(
      '''
      INSERT INTO source_platforms (
        id,
        canonical_key,
        display_name,
        kind,
        is_enabled,
        created_at,
        updated_at
      )
      VALUES (?, ?, ?, ?, ?, COALESCE(?, CURRENT_TIMESTAMP), COALESCE(?, CURRENT_TIMESTAMP))
      ON CONFLICT(id) DO UPDATE SET
        canonical_key = excluded.canonical_key,
        display_name = excluded.display_name,
        kind = excluded.kind,
        is_enabled = excluded.is_enabled,
        updated_at = COALESCE(excluded.updated_at, CURRENT_TIMESTAMP);
      ''',
      [
        record.id,
        record.canonicalKey,
        record.displayName,
        record.kind,
        record.isEnabled ? 1 : 0,
        record.createdAt,
        record.updatedAt,
      ],
    );
  }

  Future<void> upsertSourcePlatformAlias(SourcePlatformAliasRecord record) {
    return customStatement(
      '''
      INSERT INTO source_platform_aliases (
        platform_id,
        alias_key,
        alias_type,
        legacy_int_type,
        source_context,
        created_at
      )
      VALUES (?, ?, ?, ?, ?, COALESCE(?, CURRENT_TIMESTAMP))
      ON CONFLICT(alias_key, alias_type, source_context) DO UPDATE SET
        platform_id = excluded.platform_id,
        legacy_int_type = excluded.legacy_int_type;
      ''',
      [
        record.platformId,
        record.aliasKey,
        record.aliasType,
        record.legacyIntType,
        record.sourceContext,
        record.createdAt,
      ],
    );
  }

  Future<ResolvedSourcePlatform?> resolveSourcePlatform({
    String? sourceKey,
    int? legacyType,
    String sourceContext = sourceContextGlobal,
  }) async {
    if (sourceKey != null && sourceKey.isNotEmpty) {
      final byAlias = await customSelect(
        '''
        SELECT
          sp.id,
          sp.canonical_key,
          sp.display_name,
          sp.kind,
          spa.alias_key,
          spa.alias_type,
          spa.source_context,
          spa.legacy_int_type
        FROM source_platform_aliases spa
        JOIN source_platforms sp ON sp.id = spa.platform_id
        WHERE spa.alias_key = ?
          AND spa.source_context IN (?, ?)
        ORDER BY
          CASE WHEN spa.source_context = ? THEN 0 ELSE 1 END,
          CASE spa.alias_type
            WHEN 'canonical' THEN 0
            WHEN 'legacy_key' THEN 1
            WHEN 'migration' THEN 2
            WHEN 'plugin_key' THEN 3
            WHEN 'display_name' THEN 4
            WHEN 'legacy_type' THEN 5
            ELSE 99
          END
        LIMIT 1;
        ''',
        variables: [
          Variable<String>(sourceKey),
          Variable<String>(sourceContext),
          const Variable<String>(sourceContextGlobal),
          Variable<String>(sourceContext),
        ],
      ).getSingleOrNull();
      if (byAlias != null) {
        return _resolvedPlatformFromRow(byAlias);
      }
    }

    if (legacyType != null) {
      final byLegacyType = await customSelect(
        '''
        SELECT
          sp.id,
          sp.canonical_key,
          sp.display_name,
          sp.kind,
          spa.alias_key,
          spa.alias_type,
          spa.source_context,
          spa.legacy_int_type
        FROM source_platform_aliases spa
        JOIN source_platforms sp ON sp.id = spa.platform_id
        WHERE spa.legacy_int_type = ?
          AND spa.source_context IN (?, ?)
        ORDER BY CASE WHEN spa.source_context = ? THEN 0 ELSE 1 END
        LIMIT 1;
        ''',
        variables: [
          Variable<int>(legacyType),
          Variable<String>(sourceContext),
          const Variable<String>(sourceContextGlobal),
          Variable<String>(sourceContext),
        ],
      ).getSingleOrNull();
      if (byLegacyType != null) {
        return _resolvedPlatformFromRow(byLegacyType);
      }
    }

    return null;
  }

  Future<void> upsertComic(ComicRecord record) {
    return customStatement(
      '''
      INSERT INTO comics (
        id,
        title,
        normalized_title,
        cover_local_path,
        created_at,
        updated_at
      )
      VALUES (?, ?, ?, ?, COALESCE(?, CURRENT_TIMESTAMP), COALESCE(?, CURRENT_TIMESTAMP))
      ON CONFLICT(id) DO UPDATE SET
        title = excluded.title,
        normalized_title = excluded.normalized_title,
        cover_local_path = excluded.cover_local_path,
        updated_at = COALESCE(excluded.updated_at, CURRENT_TIMESTAMP);
      ''',
      [
        record.id,
        record.title,
        record.normalizedTitle,
        record.coverLocalPath,
        record.createdAt,
        record.updatedAt,
      ],
    );
  }

  Future<void> insertComicTitle(ComicTitleRecord record) {
    return customStatement(
      '''
      INSERT INTO comic_titles (
        comic_id,
        title,
        normalized_title,
        title_type,
        source_platform_id,
        created_at
      )
      VALUES (?, ?, ?, ?, ?, COALESCE(?, CURRENT_TIMESTAMP))
      ON CONFLICT(comic_id, normalized_title, title_type, source_platform_id) DO UPDATE SET
        title = excluded.title;
      ''',
      [
        record.comicId,
        record.title,
        record.normalizedTitle,
        record.titleType,
        record.sourcePlatformId,
        record.createdAt,
      ],
    );
  }

  Future<void> deleteComicTitlesForComic(String comicId) {
    return customStatement('DELETE FROM comic_titles WHERE comic_id = ?;', [
      comicId,
    ]);
  }

  Future<void> deleteChaptersForComic(String comicId) {
    return customStatement('DELETE FROM chapters WHERE comic_id = ?;', [
      comicId,
    ]);
  }

  Future<void> upsertLocalLibraryItem(LocalLibraryItemRecord record) {
    return customStatement(
      '''
      INSERT INTO local_library_items (
        id,
        comic_id,
        storage_type,
        local_root_path,
        imported_from_path,
        file_count,
        total_bytes,
        content_fingerprint,
        imported_at,
        updated_at
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, COALESCE(?, CURRENT_TIMESTAMP), COALESCE(?, CURRENT_TIMESTAMP))
      ON CONFLICT(id) DO UPDATE SET
        comic_id = excluded.comic_id,
        storage_type = excluded.storage_type,
        local_root_path = excluded.local_root_path,
        imported_from_path = excluded.imported_from_path,
        file_count = excluded.file_count,
        total_bytes = excluded.total_bytes,
        content_fingerprint = excluded.content_fingerprint,
        imported_at = COALESCE(excluded.imported_at, local_library_items.imported_at),
        updated_at = COALESCE(excluded.updated_at, CURRENT_TIMESTAMP);
      ''',
      [
        record.id,
        record.comicId,
        record.storageType,
        record.localRootPath,
        record.importedFromPath,
        record.fileCount,
        record.totalBytes,
        record.contentFingerprint,
        record.importedAt,
        record.updatedAt,
      ],
    );
  }

  Future<void> upsertFavorite(FavoriteRecord record) {
    return customStatement(
      '''
      INSERT INTO favorites (
        comic_id,
        source_key,
        created_at
      )
      VALUES (?, ?, COALESCE(?, CURRENT_TIMESTAMP))
      ON CONFLICT(comic_id) DO UPDATE SET
        source_key = excluded.source_key;
      ''',
      [record.comicId, record.sourceKey, record.createdAt],
    );
  }

  Future<void> deleteFavorite(String comicId) {
    return customStatement('DELETE FROM favorites WHERE comic_id = ?;', [
      comicId,
    ]);
  }

  Future<void> upsertChapter(ChapterRecord record) {
    return customStatement(
      '''
      INSERT INTO chapters (
        id,
        comic_id,
        chapter_no,
        title,
        normalized_title,
        created_at,
        updated_at
      )
      VALUES (?, ?, ?, ?, ?, COALESCE(?, CURRENT_TIMESTAMP), COALESCE(?, CURRENT_TIMESTAMP))
      ON CONFLICT(id) DO UPDATE SET
        comic_id = excluded.comic_id,
        chapter_no = excluded.chapter_no,
        title = excluded.title,
        normalized_title = excluded.normalized_title,
        updated_at = COALESCE(excluded.updated_at, CURRENT_TIMESTAMP);
      ''',
      [
        record.id,
        record.comicId,
        record.chapterNo,
        record.title,
        record.normalizedTitle,
        record.createdAt,
        record.updatedAt,
      ],
    );
  }

  Future<void> upsertPage(PageRecord record) {
    return customStatement(
      '''
      INSERT INTO pages (
        id,
        chapter_id,
        page_index,
        local_path,
        content_hash,
        width,
        height,
        bytes,
        created_at
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, COALESCE(?, CURRENT_TIMESTAMP))
      ON CONFLICT(id) DO UPDATE SET
        chapter_id = excluded.chapter_id,
        page_index = excluded.page_index,
        local_path = excluded.local_path,
        content_hash = excluded.content_hash,
        width = excluded.width,
        height = excluded.height,
        bytes = excluded.bytes;
      ''',
      [
        record.id,
        record.chapterId,
        record.pageIndex,
        record.localPath,
        record.contentHash,
        record.width,
        record.height,
        record.bytes,
        record.createdAt,
      ],
    );
  }

  Future<void> upsertPageOrder(PageOrderRecord record) {
    return customStatement(
      '''
      INSERT INTO page_orders (
        id,
        chapter_id,
        order_name,
        normalized_order_name,
        order_type,
        is_active,
        created_at,
        updated_at
      )
      VALUES (?, ?, ?, ?, ?, ?, COALESCE(?, CURRENT_TIMESTAMP), COALESCE(?, CURRENT_TIMESTAMP))
      ON CONFLICT(id) DO UPDATE SET
        chapter_id = excluded.chapter_id,
        order_name = excluded.order_name,
        normalized_order_name = excluded.normalized_order_name,
        order_type = excluded.order_type,
        is_active = excluded.is_active,
        updated_at = COALESCE(excluded.updated_at, CURRENT_TIMESTAMP);
      ''',
      [
        record.id,
        record.chapterId,
        record.orderName,
        record.normalizedOrderName,
        record.orderType,
        record.isActive ? 1 : 0,
        record.createdAt,
        record.updatedAt,
      ],
    );
  }

  Future<void> replacePageOrderItems(
    String pageOrderId,
    List<PageOrderItemRecord> items,
  ) async {
    await transaction(() async {
      await customStatement(
        'DELETE FROM page_order_items WHERE page_order_id = ?;',
        [pageOrderId],
      );
      for (final record in items) {
        await customStatement(
          '''
          INSERT INTO page_order_items (
            page_order_id,
            page_id,
            sort_order,
            is_hidden,
            added_at
          )
          VALUES (?, ?, ?, ?, COALESCE(?, CURRENT_TIMESTAMP));
          ''',
          [
            record.pageOrderId,
            record.pageId,
            record.sortOrder,
            record.isHidden ? 1 : 0,
            record.addedAt,
          ],
        );
      }
    });
  }

  Future<void> upsertHistoryEvent(HistoryEventRecord record) {
    return customStatement(
      '''
      INSERT INTO history_events (
        id,
        comic_id,
        source_type_value,
        source_key,
        title,
        subtitle,
        cover,
        event_time,
        chapter_index,
        page_index,
        chapter_group,
        read_episode,
        max_page,
        created_at
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, COALESCE(?, CURRENT_TIMESTAMP))
      ON CONFLICT(id) DO UPDATE SET
        comic_id = excluded.comic_id,
        source_type_value = excluded.source_type_value,
        source_key = excluded.source_key,
        title = excluded.title,
        subtitle = excluded.subtitle,
        cover = excluded.cover,
        event_time = excluded.event_time,
        chapter_index = excluded.chapter_index,
        page_index = excluded.page_index,
        chapter_group = excluded.chapter_group,
        read_episode = excluded.read_episode,
        max_page = excluded.max_page;
      ''',
      [
        record.id,
        record.comicId,
        record.sourceTypeValue,
        record.sourceKey,
        record.title,
        record.subtitle,
        record.cover,
        record.eventTime,
        record.chapterIndex,
        record.pageIndex,
        record.chapterGroup,
        record.readEpisode,
        record.maxPage,
        record.createdAt,
      ],
    );
  }

  Future<UnifiedComicSnapshot?> loadComicSnapshot(String comicId) async {
    final comicRow = await customSelect(
      'SELECT * FROM comics WHERE id = ? LIMIT 1;',
      variables: [Variable<String>(comicId)],
    ).getSingleOrNull();
    if (comicRow == null) {
      return null;
    }
    final titleRows = await customSelect(
      '''
      SELECT * FROM comic_titles
      WHERE comic_id = ?
      ORDER BY id ASC;
      ''',
      variables: [Variable<String>(comicId)],
    ).get();
    final localRows = await customSelect(
      '''
      SELECT * FROM local_library_items
      WHERE comic_id = ?
      ORDER BY imported_at ASC, id ASC;
      ''',
      variables: [Variable<String>(comicId)],
    ).get();
    final chapterRows = await customSelect(
      '''
      SELECT * FROM chapters
      WHERE comic_id = ?
      ORDER BY COALESCE(chapter_no, 1000000000) ASC, normalized_title ASC;
      ''',
      variables: [Variable<String>(comicId)],
    ).get();
    final favoriteRow = await customSelect(
      '''
      SELECT * FROM favorites
      WHERE comic_id = ?
      LIMIT 1;
      ''',
      variables: [Variable<String>(comicId)],
    ).getSingleOrNull();
    return UnifiedComicSnapshot(
      comic: _comicRecordFromRow(comicRow),
      titles: titleRows.map(_comicTitleRecordFromRow).toList(),
      localLibraryItems: localRows.map(_localLibraryItemRecordFromRow).toList(),
      favorite: favoriteRow == null
          ? null
          : _favoriteRecordFromRow(favoriteRow),
      chapters: chapterRows.map(_chapterRecordFromRow).toList(),
    );
  }

  Future<LocalLibraryItemRecord?> loadPrimaryLocalLibraryItem(
    String comicId,
  ) async {
    final row = await customSelect(
      '''
      SELECT * FROM local_library_items
      WHERE comic_id = ?
      ORDER BY updated_at DESC, imported_at DESC, id DESC
      LIMIT 1;
      ''',
      variables: [Variable<String>(comicId)],
    ).getSingleOrNull();
    if (row == null) {
      return null;
    }
    return _localLibraryItemRecordFromRow(row);
  }

  Future<PageOrderRecord?> loadActivePageOrderForChapter(
    String chapterId,
  ) async {
    final row = await customSelect(
      '''
      SELECT * FROM page_orders
      WHERE chapter_id = ?
        AND is_active = 1
      LIMIT 1;
      ''',
      variables: [Variable<String>(chapterId)],
    ).getSingleOrNull();
    if (row == null) {
      return null;
    }
    return _pageOrderRecordFromRow(row);
  }

  Future<List<PageRecord>> loadActivePageOrderPages(String chapterId) async {
    final rows = await customSelect(
      '''
      SELECT p.*
      FROM page_orders po
      JOIN page_order_items poi ON poi.page_order_id = po.id
      JOIN pages p ON p.id = poi.page_id
      WHERE po.chapter_id = ?
        AND po.is_active = 1
        AND poi.is_hidden = 0
      ORDER BY poi.sort_order ASC;
      ''',
      variables: [Variable<String>(chapterId)],
    ).get();
    return rows.map(_pageRecordFromRow).toList();
  }

  Future<bool> isComicFavorited(String comicId) async {
    final row = await customSelect(
      '''
      SELECT COUNT(*) AS c
      FROM favorites
      WHERE comic_id = ?;
      ''',
      variables: [Variable<String>(comicId)],
    ).getSingle();
    return row.read<int>('c') > 0;
  }

  Future<int> countPagesForChapter(String chapterId) async {
    final rows = await customSelect(
      'SELECT COUNT(*) AS c FROM pages WHERE chapter_id = ?;',
      variables: [Variable<String>(chapterId)],
    ).getSingle();
    return rows.read<int>('c');
  }

  Future<PageOrderSummaryRecord> loadPageOrderSummary(String comicId) async {
    final rows = await customSelect(
      '''
      SELECT
        po.id AS active_order_id,
        po.order_type AS active_order_type,
        (
          SELECT COUNT(*)
          FROM page_orders po_all
          JOIN chapters ch_all ON ch_all.id = po_all.chapter_id
          WHERE ch_all.comic_id = ?
        ) AS total_orders,
        (
          SELECT COUNT(*)
          FROM pages p
          JOIN chapters ch ON ch.id = p.chapter_id
          WHERE ch.comic_id = ?
        ) AS total_page_count,
        (
          SELECT COUNT(*)
          FROM page_order_items poi
          JOIN page_orders po_visible ON po_visible.id = poi.page_order_id
          JOIN chapters ch_visible ON ch_visible.id = po_visible.chapter_id
          WHERE ch_visible.comic_id = ?
            AND po_visible.is_active = 1
            AND poi.is_hidden = 0
        ) AS visible_page_count
      FROM page_orders po
      JOIN chapters ch ON ch.id = po.chapter_id
      WHERE ch.comic_id = ?
        AND po.is_active = 1
      ORDER BY ch.chapter_no ASC, ch.normalized_title ASC
      LIMIT 1;
      ''',
      variables: [
        Variable<String>(comicId),
        Variable<String>(comicId),
        Variable<String>(comicId),
        Variable<String>(comicId),
      ],
    ).getSingleOrNull();
    if (rows == null) {
      final fallback = await customSelect(
        '''
        SELECT
          0 AS total_orders,
          (
            SELECT COUNT(*)
            FROM pages p
            JOIN chapters ch ON ch.id = p.chapter_id
            WHERE ch.comic_id = ?
          ) AS total_page_count
        ''',
        variables: [Variable<String>(comicId)],
      ).getSingle();
      return PageOrderSummaryRecord(
        totalOrders: fallback.read<int>('total_orders'),
        totalPageCount: fallback.read<int>('total_page_count'),
        visiblePageCount: fallback.read<int>('total_page_count'),
      );
    }
    return PageOrderSummaryRecord(
      activeOrderId: rows.read<String?>('active_order_id'),
      activeOrderType: rows.read<String?>('active_order_type'),
      totalOrders: rows.read<int>('total_orders'),
      totalPageCount: rows.read<int>('total_page_count'),
      visiblePageCount: rows.read<int>('visible_page_count'),
    );
  }

  Future<HistoryEventRecord?> loadLatestHistoryEvent(String comicId) async {
    final row = await customSelect(
      '''
      SELECT * FROM history_events
      WHERE comic_id = ?
      ORDER BY event_time DESC
      LIMIT 1;
      ''',
      variables: [Variable<String>(comicId)],
    ).getSingleOrNull();
    if (row == null) {
      return null;
    }
    return _historyEventRecordFromRow(row);
  }

  ComicRecord _comicRecordFromRow(QueryRow row) {
    return ComicRecord(
      id: row.read<String>('id'),
      title: row.read<String>('title'),
      normalizedTitle: row.read<String>('normalized_title'),
      coverLocalPath: row.read<String?>('cover_local_path'),
      createdAt: row.read<String>('created_at'),
      updatedAt: row.read<String>('updated_at'),
    );
  }

  ComicTitleRecord _comicTitleRecordFromRow(QueryRow row) {
    return ComicTitleRecord(
      id: row.read<int>('id'),
      comicId: row.read<String>('comic_id'),
      title: row.read<String>('title'),
      normalizedTitle: row.read<String>('normalized_title'),
      titleType: row.read<String>('title_type'),
      sourcePlatformId: row.read<String?>('source_platform_id'),
      createdAt: row.read<String>('created_at'),
    );
  }

  LocalLibraryItemRecord _localLibraryItemRecordFromRow(QueryRow row) {
    return LocalLibraryItemRecord(
      id: row.read<String>('id'),
      comicId: row.read<String>('comic_id'),
      storageType: row.read<String>('storage_type'),
      localRootPath: row.read<String>('local_root_path'),
      importedFromPath: row.read<String?>('imported_from_path'),
      fileCount: row.read<int>('file_count'),
      totalBytes: row.read<int>('total_bytes'),
      contentFingerprint: row.read<String?>('content_fingerprint'),
      importedAt: row.read<String>('imported_at'),
      updatedAt: row.read<String>('updated_at'),
    );
  }

  FavoriteRecord _favoriteRecordFromRow(QueryRow row) {
    return FavoriteRecord(
      comicId: row.read<String>('comic_id'),
      sourceKey: row.read<String>('source_key'),
      createdAt: row.read<String>('created_at'),
    );
  }

  ChapterRecord _chapterRecordFromRow(QueryRow row) {
    return ChapterRecord(
      id: row.read<String>('id'),
      comicId: row.read<String>('comic_id'),
      chapterNo: row.read<double?>('chapter_no'),
      title: row.read<String>('title'),
      normalizedTitle: row.read<String>('normalized_title'),
      createdAt: row.read<String>('created_at'),
      updatedAt: row.read<String>('updated_at'),
    );
  }

  PageRecord _pageRecordFromRow(QueryRow row) {
    return PageRecord(
      id: row.read<String>('id'),
      chapterId: row.read<String>('chapter_id'),
      pageIndex: row.read<int>('page_index'),
      localPath: row.read<String>('local_path'),
      contentHash: row.read<String?>('content_hash'),
      width: row.read<int?>('width'),
      height: row.read<int?>('height'),
      bytes: row.read<int?>('bytes'),
      createdAt: row.read<String>('created_at'),
    );
  }

  PageOrderRecord _pageOrderRecordFromRow(QueryRow row) {
    return PageOrderRecord(
      id: row.read<String>('id'),
      chapterId: row.read<String>('chapter_id'),
      orderName: row.read<String>('order_name'),
      normalizedOrderName: row.read<String>('normalized_order_name'),
      orderType: row.read<String>('order_type'),
      isActive: row.read<int>('is_active') == 1,
      createdAt: row.read<String>('created_at'),
      updatedAt: row.read<String>('updated_at'),
    );
  }

  HistoryEventRecord _historyEventRecordFromRow(QueryRow row) {
    return HistoryEventRecord(
      id: row.read<String>('id'),
      comicId: row.read<String>('comic_id'),
      sourceTypeValue: row.read<int>('source_type_value'),
      sourceKey: row.read<String>('source_key'),
      title: row.read<String>('title'),
      subtitle: row.read<String>('subtitle'),
      cover: row.read<String>('cover'),
      eventTime: row.read<String>('event_time'),
      chapterIndex: row.read<int>('chapter_index'),
      pageIndex: row.read<int>('page_index'),
      chapterGroup: row.read<int?>('chapter_group'),
      readEpisode: row.read<String>('read_episode'),
      maxPage: row.read<int?>('max_page'),
      createdAt: row.read<String>('created_at'),
    );
  }

  ResolvedSourcePlatform _resolvedPlatformFromRow(QueryRow row) {
    return ResolvedSourcePlatform(
      platformId: row.read<String>('id'),
      canonicalKey: row.read<String>('canonical_key'),
      displayName: row.read<String>('display_name'),
      kind: row.read<String>('kind'),
      matchedAlias: row.read<String>('alias_key'),
      matchedAliasType: row.read<String>('alias_type'),
      sourceContext: row.read<String>('source_context'),
      legacyIntType: row.read<int?>('legacy_int_type'),
    );
  }
}

Iterable<SourcePlatformAliasRecord> _aliasesForDefinition(
  SourcePlatformDefinition platform,
) sync* {
  yield SourcePlatformAliasRecord(
    platformId: platform.platformId,
    aliasKey: platform.canonicalKey,
    aliasType: SourceAliasType.canonical.key,
    sourceContext: sourceContextGlobal,
  );
  for (final alias in platform.aliases) {
    for (final context in alias.contexts) {
      yield SourcePlatformAliasRecord(
        platformId: platform.platformId,
        aliasKey: alias.aliasKey,
        aliasType: alias.aliasType.key,
        legacyIntType: alias.legacyIntType,
        sourceContext: context.key,
      );
    }
  }
}
