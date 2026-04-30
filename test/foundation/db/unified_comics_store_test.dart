import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' show sqlite3;
import 'package:venera/foundation/db/unified_comics_store.dart';

void main() {
  late Directory tempDir;
  late String dbPath;
  late UnifiedComicsStore store;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('venera-unified-store-test-');
    dbPath = '${tempDir.path}/unified_comics.db';
    store = UnifiedComicsStore(dbPath);
    await store.init();
  });

  tearDown(() async {
    await store.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('init creates PR1 foundation tables', () async {
    final tables = await store.listTables();

    expect(
      tables,
      containsAll(<String>[
        'chapters',
        'chapter_source_links',
        'comic_source_links',
        'comic_source_link_tags',
        'comic_titles',
        'comic_user_tags',
        'comics',
        'eh_tag_taxonomy',
        'favorites',
        'history_events',
        'local_library_items',
        'page_order_items',
        'page_orders',
        'page_source_links',
        'pages',
        'reader_sessions',
        'reader_tabs',
        'remote_match_candidates',
        'source_tags',
        'source_platform_aliases',
        'source_platforms',
        'user_tags',
      ]),
    );
    expect(tables, isNot(contains('comic_sources')));
    expect(await store.currentUserVersion(), store.schemaVersion);
  });

  test('concurrent init on same instance is safe', () async {
    await Future.wait<void>([store.init(), store.init(), store.init()]);

    expect(await store.currentUserVersion(), store.schemaVersion);
  });

  test('init recreates missing favorite folder tables for legacy dbs', () async {
    final raw = sqlite3.open(dbPath);
    raw.execute('DROP TABLE IF EXISTS favorite_folder_items;');
    raw.dispose();

    await store.init();

    final tables = await store.listTables();
    expect(tables, contains('favorite_folder_items'));

    await expectLater(
      store.deleteFavoriteFolderItemsByComic('non-existent-comic'),
      completes,
    );
  });

  test('foreign key enforcement is enabled on store connection', () async {
    expect(await store.foreignKeysEnabled(), 1);

    await expectLater(
      store.upsertSourcePlatformAlias(
        const SourcePlatformAliasRecord(
          platformId: 'missing-platform',
          aliasKey: 'bad',
          aliasType: 'canonical',
        ),
      ),
      throwsA(
        predicate(
          (error) => error.toString().contains('FOREIGN KEY constraint failed'),
        ),
      ),
    );
  });

  test('store uses WAL and canonical data path helper', () async {
    expect(
      canonicalDomainDatabasePath('/app/support'),
      '/app/support/data/venera.db',
    );
    expect(await store.currentJournalMode(), 'wal');
    expect(await store.foreignKeysEnabled(), 1);
  });

  test('comic source links include V1 citation columns', () async {
    final columns = await store.listColumns('comic_source_links');

    expect(
      columns,
      containsAll(<String>[
        'source_url',
        'source_title',
        'downloaded_at',
        'last_verified_at',
      ]),
    );
  });

  test(
    'seeded resolver handles canonical, legacy key, and context-specific legacy type',
    () async {
      await store.seedDefaultSourcePlatforms();

      final canonical = await store.resolveSourcePlatform(sourceKey: 'picacg');
      final legacyKey = await store.resolveSourcePlatform(sourceKey: 'pica');
      final historyLegacy = await store.resolveSourcePlatform(
        legacyType: 5,
        sourceContext: 'history',
      );
      final favoriteLegacy = await store.resolveSourcePlatform(
        legacyType: 6,
        sourceContext: 'favorite',
      );
      final importedMigration = await store.resolveSourcePlatform(
        sourceKey: 'htmanga',
        sourceContext: 'import',
      );

      expect(canonical?.platformId, 'picacg');
      expect(canonical?.matchedAliasType, 'canonical');
      expect(legacyKey?.platformId, 'picacg');
      expect(legacyKey?.matchedAliasType, 'legacy_key');
      expect(historyLegacy?.platformId, 'nhentai');
      expect(historyLegacy?.sourceContext, 'history');
      expect(favoriteLegacy?.platformId, 'nhentai');
      expect(favoriteLegacy?.legacyIntType, 6);
      expect(importedMigration?.platformId, 'wnacg');
      expect(importedMigration?.matchedAliasType, 'migration');
    },
  );

  test(
    'comic snapshot readback includes titles local library items and favorite state',
    () async {
      await store.seedDefaultSourcePlatforms();
      await store.upsertComic(
        const ComicRecord(
          id: 'comic-1',
          title: 'My Comic',
          normalizedTitle: 'my comic',
          coverLocalPath: '/covers/1.jpg',
        ),
      );
      await store.insertComicTitle(
        const ComicTitleRecord(
          comicId: 'comic-1',
          title: 'My Comic',
          normalizedTitle: 'my comic',
          titleType: 'primary',
        ),
      );
      await store.insertComicTitle(
        const ComicTitleRecord(
          comicId: 'comic-1',
          title: 'Imported File Name',
          normalizedTitle: 'imported file name',
          titleType: 'imported_filename',
          sourcePlatformId: 'local',
        ),
      );
      await store.upsertLocalLibraryItem(
        const LocalLibraryItemRecord(
          id: 'local-1',
          comicId: 'comic-1',
          storageType: 'user_imported',
          localRootPath: '/library/comic-1',
          importedFromPath: '/imports/comic-1.cbz',
          fileCount: 27,
          totalBytes: 4096,
          contentFingerprint: 'fp-1',
        ),
      );
      await store.upsertFavorite(
        const FavoriteRecord(comicId: 'comic-1', sourceKey: 'local'),
      );

      final snapshot = await store.loadComicSnapshot('comic-1');

      expect(snapshot, isNotNull);
      expect(snapshot?.comic.title, 'My Comic');
      expect(snapshot?.titles.map((title) => title.titleType).toList(), [
        'primary',
        'imported_filename',
      ]);
      expect(snapshot?.localLibraryItems.single.storageType, 'user_imported');
      expect(snapshot?.localLibraryItems.single.fileCount, 27);
      expect(snapshot?.favorite?.comicId, 'comic-1');
      expect(snapshot?.favorite?.sourceKey, 'local');
      expect(await store.isComicFavorited('comic-1'), isTrue);
    },
  );

  test(
    'comic delete cascades into titles local library items and favorites',
    () async {
      final db = sqlite3.open(dbPath);
      addTearDown(db.dispose);

      await store.upsertComic(
        const ComicRecord(
          id: 'comic-cascade',
          title: 'Cascade',
          normalizedTitle: 'cascade',
        ),
      );
      await store.insertComicTitle(
        const ComicTitleRecord(
          comicId: 'comic-cascade',
          title: 'Cascade',
          normalizedTitle: 'cascade',
          titleType: 'primary',
        ),
      );
      await store.upsertLocalLibraryItem(
        const LocalLibraryItemRecord(
          id: 'local-cascade',
          comicId: 'comic-cascade',
          storageType: 'downloaded',
          localRootPath: '/library/cascade',
        ),
      );
      await store.upsertFavorite(
        const FavoriteRecord(comicId: 'comic-cascade', sourceKey: 'local'),
      );

      db.execute('PRAGMA foreign_keys = ON;');
      db.execute('DELETE FROM comics WHERE id = ?;', ['comic-cascade']);

      final titleCount =
          db.select(
                'SELECT COUNT(*) AS c FROM comic_titles WHERE comic_id = ?;',
                ['comic-cascade'],
              ).single['c']
              as int;
      final localCount =
          db.select(
                'SELECT COUNT(*) AS c FROM local_library_items WHERE comic_id = ?;',
                ['comic-cascade'],
              ).single['c']
              as int;
      final favoriteCount =
          db.select('SELECT COUNT(*) AS c FROM favorites WHERE comic_id = ?;', [
                'comic-cascade',
              ]).single['c']
              as int;
      expect(titleCount, 0);
      expect(localCount, 0);
      expect(favoriteCount, 0);
    },
  );

  test('loads primary local library item for comic by newest update', () async {
    await _insertReaderFixture(store);
    await store.upsertLocalLibraryItem(
      const LocalLibraryItemRecord(
        id: 'local-item-newer',
        comicId: 'comic-1',
        storageType: 'user_imported',
        localRootPath: '/library/comic-1-newer',
        updatedAt: '2026-04-30 10:00:00',
      ),
    );

    final item = await store.loadPrimaryLocalLibraryItem('comic-1');

    expect(item?.id, 'local-item-newer');
    expect(item?.localRootPath, '/library/comic-1-newer');
  });

  test('can upsert and read primary comic source link', () async {
    await store.upsertSourcePlatform(
      const SourcePlatformRecord(
        id: 'platform-a',
        canonicalKey: 'platform-a',
        displayName: 'Platform A',
        kind: 'remote',
      ),
    );
    await store.upsertComic(
      const ComicRecord(
        id: 'comic-source-1',
        title: 'Source Comic',
        normalizedTitle: 'source comic',
      ),
    );
    await store.upsertComicSourceLink(
      const ComicSourceLinkRecord(
        id: 'link-1',
        comicId: 'comic-source-1',
        sourcePlatformId: 'platform-a',
        sourceComicId: 'remote-123',
        linkStatus: 'active',
        isPrimary: true,
        sourceUrl: 'https://example.com/comic/remote-123',
        sourceTitle: 'Remote Title',
        downloadedAt: '2026-04-30T12:00:00.000Z',
        lastVerifiedAt: '2026-04-30T13:00:00.000Z',
        metadataJson: '{"origin":"import"}',
      ),
    );

    final primary = await store.loadPrimaryComicSourceLink('comic-source-1');
    final all = await store.loadComicSourceLinks('comic-source-1');

    expect(primary, isNotNull);
    expect(primary?.id, 'link-1');
    expect(primary?.isPrimary, isTrue);
    expect(primary?.sourcePlatformId, 'platform-a');
    expect(primary?.sourceComicId, 'remote-123');
    expect(primary?.sourceUrl, 'https://example.com/comic/remote-123');
    expect(primary?.sourceTitle, 'Remote Title');
    expect(primary?.downloadedAt, '2026-04-30T12:00:00.000Z');
    expect(primary?.lastVerifiedAt, '2026-04-30T13:00:00.000Z');
    expect(primary?.metadataJson, '{"origin":"import"}');
    expect(all.length, 1);
  });

  test(
    'primary ordering keeps primary first when multiple links exist',
    () async {
      await store.upsertSourcePlatform(
        const SourcePlatformRecord(
          id: 'platform-a',
          canonicalKey: 'platform-a',
          displayName: 'Platform A',
          kind: 'remote',
        ),
      );
      await store.upsertSourcePlatform(
        const SourcePlatformRecord(
          id: 'platform-b',
          canonicalKey: 'platform-b',
          displayName: 'Platform B',
          kind: 'remote',
        ),
      );
      await store.upsertComic(
        const ComicRecord(
          id: 'comic-source-2',
          title: 'Source Comic 2',
          normalizedTitle: 'source comic 2',
        ),
      );
      await store.upsertComicSourceLink(
        const ComicSourceLinkRecord(
          id: 'link-a',
          comicId: 'comic-source-2',
          sourcePlatformId: 'platform-a',
          sourceComicId: 'a-1',
          isPrimary: false,
        ),
      );
      await store.upsertComicSourceLink(
        const ComicSourceLinkRecord(
          id: 'link-b',
          comicId: 'comic-source-2',
          sourcePlatformId: 'platform-b',
          sourceComicId: 'b-1',
          isPrimary: true,
        ),
      );

      final links = await store.loadComicSourceLinks('comic-source-2');
      final primary = await store.loadPrimaryComicSourceLink('comic-source-2');

      expect(links.length, 2);
      expect(links.first.id, 'link-b');
      expect(links.first.isPrimary, isTrue);
      expect(links.last.id, 'link-a');
      expect(links.last.isPrimary, isFalse);
      expect(primary?.id, 'link-b');
    },
  );

  test('legacy comic_source_links rows survive V1 column extension', () async {
    final legacyPath = '${tempDir.path}/legacy_source_links.db';
    final legacyDb = sqlite3.open(legacyPath);
    addTearDown(legacyDb.dispose);
    legacyDb.execute('PRAGMA foreign_keys = ON;');
    legacyDb.execute('''
      CREATE TABLE source_platforms (
        id TEXT PRIMARY KEY,
        canonical_key TEXT NOT NULL UNIQUE,
        display_name TEXT NOT NULL,
        kind TEXT NOT NULL,
        is_enabled INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
      );
    ''');
    legacyDb.execute('''
      CREATE TABLE comics (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        normalized_title TEXT NOT NULL,
        cover_local_path TEXT,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
      );
    ''');
    legacyDb.execute('''
      CREATE TABLE comic_source_links (
        id TEXT PRIMARY KEY,
        comic_id TEXT NOT NULL,
        source_platform_id TEXT NOT NULL,
        source_comic_id TEXT NOT NULL,
        link_status TEXT NOT NULL DEFAULT 'active',
        is_primary INTEGER NOT NULL DEFAULT 0,
        linked_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        metadata_json TEXT,
        FOREIGN KEY (comic_id) REFERENCES comics(id) ON DELETE CASCADE,
        FOREIGN KEY (source_platform_id) REFERENCES source_platforms(id) ON DELETE RESTRICT,
        UNIQUE(comic_id, source_platform_id, source_comic_id)
      );
    ''');
    legacyDb.execute(
      '''
      INSERT INTO source_platforms (id, canonical_key, display_name, kind)
      VALUES (?, ?, ?, ?);
      ''',
      ['platform-old', 'platform-old', 'Platform Old', 'remote'],
    );
    legacyDb.execute(
      '''
      INSERT INTO comics (id, title, normalized_title)
      VALUES (?, ?, ?);
      ''',
      ['comic-old', 'Old Comic', 'old comic'],
    );
    legacyDb.execute(
      '''
      INSERT INTO comic_source_links (
        id, comic_id, source_platform_id, source_comic_id, link_status, is_primary, metadata_json
      )
      VALUES (?, ?, ?, ?, ?, ?, ?);
      ''',
      [
        'legacy-link',
        'comic-old',
        'platform-old',
        'legacy-123',
        'active',
        1,
        '{"legacy":true}',
      ],
    );
    legacyDb.execute('PRAGMA user_version = 1;');
    legacyDb.dispose();

    await store.close();
    store = UnifiedComicsStore(legacyPath);
    await store.init();

    final link = await store.loadPrimaryComicSourceLink('comic-old');

    expect(link, isNotNull);
    expect(link?.id, 'legacy-link');
    expect(link?.sourceComicId, 'legacy-123');
    expect(link?.metadataJson, '{"legacy":true}');
    expect(await store.currentUserVersion(), store.schemaVersion);
  });

  test(
    'legacy v2 database upgrades to v3 reader and remote match schema',
    () async {
      final legacyPath = '${tempDir.path}/legacy_v2.db';
      final legacyDb = sqlite3.open(legacyPath);
      addTearDown(legacyDb.dispose);
      legacyDb.execute('PRAGMA foreign_keys = ON;');
      legacyDb.execute('''
      CREATE TABLE source_platforms (
        id TEXT PRIMARY KEY,
        canonical_key TEXT NOT NULL UNIQUE,
        display_name TEXT NOT NULL,
        kind TEXT NOT NULL,
        is_enabled INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
      );
    ''');
      legacyDb.execute('''
      CREATE TABLE comics (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        normalized_title TEXT NOT NULL,
        cover_local_path TEXT,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
      );
    ''');
      legacyDb.execute('''
      CREATE TABLE comic_source_links (
        id TEXT PRIMARY KEY,
        comic_id TEXT NOT NULL,
        source_platform_id TEXT NOT NULL,
        source_comic_id TEXT NOT NULL,
        link_status TEXT NOT NULL DEFAULT 'active',
        is_primary INTEGER NOT NULL DEFAULT 0,
        source_url TEXT,
        source_title TEXT,
        downloaded_at TEXT,
        last_verified_at TEXT,
        linked_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        metadata_json TEXT,
        UNIQUE(comic_id, source_platform_id, source_comic_id)
      );
    ''');
      legacyDb.execute(
        '''
      INSERT INTO comics (id, title, normalized_title)
      VALUES (?, ?, ?);
      ''',
        ['legacy-v2-comic', 'Legacy V2', 'legacy v2'],
      );
      legacyDb.execute('PRAGMA user_version = 2;');
      legacyDb.dispose();

      await store.close();
      store = UnifiedComicsStore(legacyPath);
      await store.init();

      final tables = await store.listTables();
      expect(
        tables,
        containsAll(<String>[
          'reader_sessions',
          'reader_tabs',
          'remote_match_candidates',
        ]),
      );
      expect(await store.currentUserVersion(), store.schemaVersion);
    },
  );

  test(
    'source tags stay scoped to comic source link and user tags stay separate',
    () async {
      await store.upsertSourcePlatform(
        const SourcePlatformRecord(
          id: 'platform-tags',
          canonicalKey: 'platform-tags',
          displayName: 'Platform Tags',
          kind: 'remote',
        ),
      );
      await store.upsertComic(
        const ComicRecord(
          id: 'comic-tags',
          title: 'Comic Tags',
          normalizedTitle: 'comic tags',
        ),
      );
      await store.upsertComicSourceLink(
        const ComicSourceLinkRecord(
          id: 'link-tags-a',
          comicId: 'comic-tags',
          sourcePlatformId: 'platform-tags',
          sourceComicId: 'remote-a',
          isPrimary: true,
        ),
      );
      await store.upsertComicSourceLink(
        const ComicSourceLinkRecord(
          id: 'link-tags-b',
          comicId: 'comic-tags',
          sourcePlatformId: 'platform-tags',
          sourceComicId: 'remote-b',
        ),
      );
      await store.upsertSourceTag(
        const SourceTagRecord(
          id: 'source-tag-a',
          sourcePlatformId: 'platform-tags',
          namespace: 'female',
          tagKey: 'heroine',
          displayName: 'heroine',
        ),
      );
      await store.upsertSourceTag(
        const SourceTagRecord(
          id: 'source-tag-b',
          sourcePlatformId: 'platform-tags',
          namespace: 'male',
          tagKey: 'rival',
          displayName: 'rival',
        ),
      );
      await store.attachSourceTagToComicSourceLink(
        const ComicSourceLinkTagRecord(
          comicSourceLinkId: 'link-tags-a',
          sourceTagId: 'source-tag-a',
        ),
      );
      await store.attachSourceTagToComicSourceLink(
        const ComicSourceLinkTagRecord(
          comicSourceLinkId: 'link-tags-b',
          sourceTagId: 'source-tag-b',
        ),
      );
      await store.upsertUserTag(
        const UserTagRecord(
          id: 'user-tag-a',
          name: 'reading',
          normalizedName: 'reading',
        ),
      );
      await store.attachUserTagToComic(
        const ComicUserTagRecord(
          comicId: 'comic-tags',
          userTagId: 'user-tag-a',
        ),
      );

      final linkATags = await store.loadSourceTagsForComicSourceLink(
        'link-tags-a',
      );
      final linkBTags = await store.loadSourceTagsForComicSourceLink(
        'link-tags-b',
      );
      final userTags = await store.loadUserTagsForComic('comic-tags');

      expect(linkATags.map((tag) => tag.displayName), ['heroine']);
      expect(linkBTags.map((tag) => tag.displayName), ['rival']);
      expect(userTags.map((tag) => tag.name), ['reading']);
    },
  );

  test(
    'eh tag taxonomy and local library browse records round-trip canonical data',
    () async {
      await store.upsertSourcePlatform(
        const SourcePlatformRecord(
          id: 'ehentai',
          canonicalKey: 'ehentai',
          displayName: 'E-Hentai',
          kind: 'remote',
        ),
      );
      await store.upsertComic(
        const ComicRecord(
          id: 'comic-browse',
          title: 'Browse Comic',
          normalizedTitle: 'browse comic',
        ),
      );
      await store.upsertLocalLibraryItem(
        const LocalLibraryItemRecord(
          id: 'local-browse',
          comicId: 'comic-browse',
          storageType: 'user_imported',
          localRootPath: '/library/browse',
          updatedAt: '2026-04-30T10:00:00.000Z',
        ),
      );
      await store.upsertComicSourceLink(
        const ComicSourceLinkRecord(
          id: 'browse-link',
          comicId: 'comic-browse',
          sourcePlatformId: 'ehentai',
          sourceComicId: 'eh-1',
          isPrimary: true,
        ),
      );
      await store.upsertSourceTag(
        const SourceTagRecord(
          id: 'browse-source-tag',
          sourcePlatformId: 'ehentai',
          namespace: 'female',
          tagKey: 'glasses',
          displayName: 'glasses',
        ),
      );
      await store.attachSourceTagToComicSourceLink(
        const ComicSourceLinkTagRecord(
          comicSourceLinkId: 'browse-link',
          sourceTagId: 'browse-source-tag',
        ),
      );
      await store.upsertUserTag(
        const UserTagRecord(
          id: 'browse-user-tag',
          name: 'queued',
          normalizedName: 'queued',
        ),
      );
      await store.attachUserTagToComic(
        const ComicUserTagRecord(
          comicId: 'comic-browse',
          userTagId: 'browse-user-tag',
        ),
      );
      await store.replaceEhTagTaxonomyRecords(_ehentaiProvider, const [
        EhTagTaxonomyRecord(
          providerKey: _ehentaiProvider,
          locale: 'zh_CN',
          namespace: 'female',
          tagKey: 'glasses',
          translatedLabel: '眼镜',
          sourceSha: 'sha-1',
          sourceVersion: 7,
        ),
      ]);

      final taxonomy = await store.loadEhTagTaxonomy(
        providerKey: _ehentaiProvider,
        locale: 'zh_CN',
      );
      final browseRows = await store.loadLocalLibraryBrowseRecords();

      expect(taxonomy.single.translatedLabel, '眼镜');
      expect(taxonomy.single.sourceSha, 'sha-1');
      expect(browseRows.single.comicId, 'comic-browse');
      expect(browseRows.single.userTags, ['queued']);
      expect(browseRows.single.sourceTags, ['female:glasses']);
    },
  );

  test('loads active visible pages in page-order sequence', () async {
    await _insertReaderFixture(store);

    final activeOrder = await store.loadActivePageOrderForChapter('chapter-1');
    final pages = await store.loadActivePageOrderPages('chapter-1');

    expect(activeOrder?.id, 'order-1');
    expect(pages.map((page) => page.id), ['page-b', 'page-a']);
    expect(pages.map((page) => page.localPath), [
      '/library/comic-1/1.png',
      '/library/comic-1/2.png',
    ]);
  });

  test('active page-order reader excludes hidden pages', () async {
    await _insertReaderFixture(
      store,
      orderItems: const [
        PageOrderItemRecord(
          pageOrderId: 'order-1',
          pageId: 'page-b',
          sortOrder: 0,
        ),
        PageOrderItemRecord(
          pageOrderId: 'order-1',
          pageId: 'page-a',
          sortOrder: 1,
          isHidden: true,
        ),
      ],
    );

    final pages = await store.loadActivePageOrderPages('chapter-1');

    expect(pages.map((page) => page.id), ['page-b']);
  });

  test(
    'active page-order reader returns no fallback pages without active order',
    () async {
      await _insertReaderFixture(store, createPageOrder: false);

      final activeOrder = await store.loadActivePageOrderForChapter(
        'chapter-1',
      );
      final pages = await store.loadActivePageOrderPages('chapter-1');

      expect(activeOrder, isNull);
      expect(pages, isEmpty);
    },
  );

  test(
    'replacePageOrderItems rewrites order membership without stale rows',
    () async {
      await _insertReaderFixture(store);
      await store.upsertPage(
        const PageRecord(
          id: 'page-c',
          chapterId: 'chapter-1',
          pageIndex: 2,
          localPath: '/library/comic-1/3.png',
        ),
      );

      await store.replacePageOrderItems('order-1', const [
        PageOrderItemRecord(
          pageOrderId: 'order-1',
          pageId: 'page-c',
          sortOrder: 0,
        ),
      ]);

      final pages = await store.loadActivePageOrderPages('chapter-1');
      expect(pages.map((page) => page.id), ['page-c']);
    },
  );

  test(
    'reader session rows can be inserted and read before tabs exist',
    () async {
      await store.upsertComic(
        const ComicRecord(
          id: 'session-comic-1',
          title: 'Session Comic',
          normalizedTitle: 'session comic',
        ),
      );
      await store.upsertReaderSession(
        const ReaderSessionRecord(id: 'session-1', comicId: 'session-comic-1'),
      );

      final session = await store.loadReaderSessionByComic('session-comic-1');
      final tabs = await store.loadReaderTabsForSession('session-1');

      expect(session, isNotNull);
      expect(session?.id, 'session-1');
      expect(session?.activeTabId, isNull);
      expect(tabs, isEmpty);
    },
  );

  test(
    'reader tabs stay scoped to their session and ordered deterministically',
    () async {
      await store.upsertComic(
        const ComicRecord(
          id: 'session-comic-2',
          title: 'Session Comic Two',
          normalizedTitle: 'session comic two',
        ),
      );
      await store.upsertReaderSession(
        const ReaderSessionRecord(id: 'session-2', comicId: 'session-comic-2'),
      );
      await store.upsertReaderSession(
        const ReaderSessionRecord(id: 'session-3', comicId: 'session-comic-2'),
      );
      await store.upsertReaderTab(
        const ReaderTabRecord(
          id: 'tab-1',
          sessionId: 'session-2',
          comicId: 'session-comic-2',
          chapterId: 'chapter-1',
          pageIndex: 1,
          sourceRefJson: '{"id":"tab-1"}',
          createdAt: '2026-04-30T10:00:00.000Z',
          updatedAt: '2026-04-30T10:00:00.000Z',
        ),
      );
      await store.upsertReaderTab(
        const ReaderTabRecord(
          id: 'tab-2',
          sessionId: 'session-2',
          comicId: 'session-comic-2',
          chapterId: 'chapter-2',
          pageIndex: 2,
          sourceRefJson: '{"id":"tab-2"}',
          createdAt: '2026-04-30T11:00:00.000Z',
          updatedAt: '2026-04-30T11:00:00.000Z',
        ),
      );
      await store.upsertReaderTab(
        const ReaderTabRecord(
          id: 'tab-other',
          sessionId: 'session-3',
          comicId: 'session-comic-2',
          chapterId: 'chapter-3',
          pageIndex: 3,
          sourceRefJson: '{"id":"tab-other"}',
        ),
      );

      final tabs = await store.loadReaderTabsForSession('session-2');

      expect(tabs.map((tab) => tab.id), ['tab-2', 'tab-1']);
    },
  );

  test('active tab can be set only after the target tab exists', () async {
    await store.upsertComic(
      const ComicRecord(
        id: 'session-comic-3',
        title: 'Session Comic Three',
        normalizedTitle: 'session comic three',
      ),
    );
    await store.upsertReaderSession(
      const ReaderSessionRecord(id: 'session-4', comicId: 'session-comic-3'),
    );

    await expectLater(
      store.setReaderSessionActiveTab(
        sessionId: 'session-4',
        activeTabId: 'missing-tab',
      ),
      throwsA(isA<StateError>()),
    );

    await store.upsertReaderTab(
      const ReaderTabRecord(
        id: 'tab-3',
        sessionId: 'session-4',
        comicId: 'session-comic-3',
        chapterId: 'chapter-1',
        pageIndex: 5,
        sourceRefJson: '{"id":"tab-3"}',
      ),
    );
    await store.setReaderSessionActiveTab(
      sessionId: 'session-4',
      activeTabId: 'tab-3',
    );

    final session = await store.loadReaderSessionByComic('session-comic-3');
    expect(session?.activeTabId, 'tab-3');
  });

  test('deleting a session cascades to its tabs', () async {
    await store.upsertComic(
      const ComicRecord(
        id: 'session-comic-4',
        title: 'Session Comic Four',
        normalizedTitle: 'session comic four',
      ),
    );
    await store.upsertReaderSession(
      const ReaderSessionRecord(id: 'session-5', comicId: 'session-comic-4'),
    );
    await store.upsertReaderTab(
      const ReaderTabRecord(
        id: 'tab-4',
        sessionId: 'session-5',
        comicId: 'session-comic-4',
        chapterId: 'chapter-1',
        pageIndex: 0,
        sourceRefJson: '{"id":"tab-4"}',
      ),
    );

    await store.deleteReaderSession('session-5');

    expect(await store.loadReaderSessionByComic('session-comic-4'), isNull);
    expect(await store.loadReaderTabsForSession('session-5'), isEmpty);
  });

  test(
    'deleting the active tab clears the session active tab pointer',
    () async {
      await store.upsertComic(
        const ComicRecord(
          id: 'session-comic-5',
          title: 'Session Comic Five',
          normalizedTitle: 'session comic five',
        ),
      );
      await store.upsertReaderSession(
        const ReaderSessionRecord(id: 'session-6', comicId: 'session-comic-5'),
      );
      await store.upsertReaderTab(
        const ReaderTabRecord(
          id: 'tab-5',
          sessionId: 'session-6',
          comicId: 'session-comic-5',
          chapterId: 'chapter-1',
          pageIndex: 9,
          sourceRefJson: '{"id":"tab-5"}',
        ),
      );
      await store.setReaderSessionActiveTab(
        sessionId: 'session-6',
        activeTabId: 'tab-5',
      );

      await store.deleteReaderTab('tab-5');

      final session = await store.loadReaderSessionByComic('session-comic-5');
      expect(session?.activeTabId, isNull);
    },
  );

  test('remote match candidates can be inserted and listed by comic', () async {
    await store.upsertComic(
      const ComicRecord(
        id: 'candidate-comic-1',
        title: 'Candidate Comic',
        normalizedTitle: 'candidate comic',
      ),
    );
    await store.upsertSourcePlatform(
      const SourcePlatformRecord(
        id: 'copymanga',
        canonicalKey: 'copymanga',
        displayName: 'CopyManga',
        kind: 'remote',
      ),
    );
    await store.upsertRemoteMatchCandidate(
      const RemoteMatchCandidateRecord(
        id: 'candidate-1',
        comicId: 'candidate-comic-1',
        sourcePlatformId: 'copymanga',
        sourceComicId: 'remote-1',
        sourceUrl: 'https://example.com/comic/remote-1',
        sourceTitle: 'Remote One',
        confidence: 0.93,
        metadataJson: '{"note":"first"}',
        status: 'pending',
      ),
    );

    final candidates = await store.loadRemoteMatchCandidates(
      'candidate-comic-1',
    );

    expect(candidates, hasLength(1));
    expect(candidates.single.id, 'candidate-1');
    expect(candidates.single.sourceComicId, 'remote-1');
    expect(candidates.single.status, 'pending');
  });
}

const _ehentaiProvider = 'ehentai';

Future<void> _insertReaderFixture(
  UnifiedComicsStore store, {
  bool createPageOrder = true,
  List<PageOrderItemRecord> orderItems = const [
    PageOrderItemRecord(pageOrderId: 'order-1', pageId: 'page-b', sortOrder: 0),
    PageOrderItemRecord(pageOrderId: 'order-1', pageId: 'page-a', sortOrder: 1),
  ],
}) async {
  await store.upsertComic(
    const ComicRecord(
      id: 'comic-1',
      title: 'Comic One',
      normalizedTitle: 'comic one',
    ),
  );
  await store.upsertLocalLibraryItem(
    const LocalLibraryItemRecord(
      id: 'local-item-old',
      comicId: 'comic-1',
      storageType: 'user_imported',
      localRootPath: '/library/comic-1',
      updatedAt: '2026-04-30 09:00:00',
    ),
  );
  await store.upsertChapter(
    const ChapterRecord(
      id: 'chapter-1',
      comicId: 'comic-1',
      chapterNo: 1,
      title: 'Chapter 1',
      normalizedTitle: 'chapter 1',
    ),
  );
  await store.upsertPage(
    const PageRecord(
      id: 'page-a',
      chapterId: 'chapter-1',
      pageIndex: 0,
      localPath: '/library/comic-1/2.png',
    ),
  );
  await store.upsertPage(
    const PageRecord(
      id: 'page-b',
      chapterId: 'chapter-1',
      pageIndex: 1,
      localPath: '/library/comic-1/1.png',
    ),
  );
  if (!createPageOrder) {
    return;
  }
  await store.upsertPageOrder(
    const PageOrderRecord(
      id: 'order-1',
      chapterId: 'chapter-1',
      orderName: 'Source Default',
      normalizedOrderName: 'source default',
      orderType: 'source_default',
      isActive: true,
    ),
  );
  await store.replacePageOrderItems('order-1', orderItems);
}
