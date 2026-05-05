import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' show sqlite3;
import 'package:venera/foundation/database/app_db_helper.dart';
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
        'cache_entries',
        'app_settings',
        'comic_source_links',
        'comic_source_link_tags',
        'comic_titles',
        'comic_user_tags',
        'comics',
        'eh_tag_taxonomy',
        'favorites',
        'history_events',
        'implicit_data',
        'local_library_items',
        'page_order_items',
        'page_orders',
        'page_source_links',
        'pages',
        'reader_sessions',
        'reader_tabs',
        'remote_match_candidates',
        'source_tags',
        'source_repositories',
        'source_packages',
        'search_history',
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

  test(
    'init recreates missing favorite folder tables for legacy dbs',
    () async {
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
    },
  );

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

  test(
    'cache entry lifecycle supports upsert touch delete and clear',
    () async {
      const first = CacheEntryRecord(
        cacheKey: 'cache-key-1',
        namespace: 'reader',
        sourcePlatformId: 'local',
        ownerRef: 'comic-1',
        remoteUrlHash: 'hash-a',
        storageDir: '/tmp/cache',
        fileName: 'file-a.jpg',
        expiresAtMs: 1000,
        contentType: 'image/jpeg',
        sizeBytes: 10,
        createdAtMs: 1,
        lastAccessedAtMs: 2,
      );
      await store.upsertCacheEntry(first);

      final loaded1 = await store.loadCacheEntry(first.cacheKey);
      expect(loaded1, isNotNull);
      expect(loaded1?.fileName, 'file-a.jpg');

      const second = CacheEntryRecord(
        cacheKey: 'cache-key-1',
        namespace: 'reader',
        sourcePlatformId: 'local',
        ownerRef: 'comic-1',
        remoteUrlHash: 'hash-b',
        storageDir: '/tmp/cache',
        fileName: 'file-b.jpg',
        expiresAtMs: 2000,
        contentType: 'image/webp',
        sizeBytes: 20,
        createdAtMs: 1,
        lastAccessedAtMs: 3,
      );
      await store.upsertCacheEntry(second);
      await store.touchCacheEntryAccess(
        cacheKey: second.cacheKey,
        expiresAtMs: 3000,
        lastAccessedAtMs: 4,
      );

      final loaded2 = await store.loadCacheEntry(second.cacheKey);
      expect(loaded2, isNotNull);
      expect(loaded2?.fileName, 'file-b.jpg');
      expect(loaded2?.expiresAtMs, 3000);
      expect(loaded2?.lastAccessedAtMs, 4);

      await store.deleteCacheEntry(second.cacheKey);
      expect(await store.loadCacheEntry(second.cacheKey), isNull);

      await store.upsertCacheEntry(
        const CacheEntryRecord(
          cacheKey: 'cache-key-2',
          namespace: 'reader',
          storageDir: '/tmp/cache',
          fileName: 'file-c.jpg',
          expiresAtMs: 4000,
          createdAtMs: 5,
        ),
      );
      await store.deleteAllCacheEntries();
      expect(await store.loadCacheEntry('cache-key-2'), isNull);
    },
  );

  test('app settings KV upsert overwrite and clear work', () async {
    await store.upsertAppSetting(
      const AppSettingRecord(
        key: 'feature_x',
        valueJson: '{"enabled":false}',
        valueType: 'json',
        syncPolicy: 'local',
        updatedAtMs: 10,
      ),
    );
    await store.upsertAppSetting(
      const AppSettingRecord(
        key: 'feature_x',
        valueJson: '{"enabled":true}',
        valueType: 'json',
        syncPolicy: 'local',
        updatedAtMs: 20,
      ),
    );

    final settings = await store.loadAppSettings();
    expect(settings, hasLength(1));
    expect(settings.single.valueJson, '{"enabled":true}');
    expect(settings.single.updatedAtMs, 20);

    await store.clearAppSettings();
    expect(await store.loadAppSettings(), isEmpty);
  });

  test('search history upsert ordering and clear work', () async {
    await store.upsertSearchHistory(
      const SearchHistoryRecord(keyword: 'alpha', position: 2, updatedAtMs: 10),
    );
    await store.upsertSearchHistory(
      const SearchHistoryRecord(keyword: 'beta', position: 1, updatedAtMs: 20),
    );
    await store.upsertSearchHistory(
      const SearchHistoryRecord(keyword: 'alpha', position: 0, updatedAtMs: 30),
    );

    final rows = await store.loadSearchHistory();
    expect(rows.map((row) => row.keyword).toList(), ['alpha', 'beta']);
    expect(rows.first.position, 0);
    expect(rows.first.updatedAtMs, 30);

    await store.clearSearchHistory();
    expect(await store.loadSearchHistory(), isEmpty);
  });

  test('implicit data upsert is idempotent and clear works', () async {
    await store.upsertImplicitData(
      const ImplicitDataRecord(key: 'k1', valueJson: '{"v":1}', updatedAtMs: 1),
    );
    await store.upsertImplicitData(
      const ImplicitDataRecord(key: 'k1', valueJson: '{"v":2}', updatedAtMs: 2),
    );

    final rows = await store.loadImplicitData();
    expect(rows, hasLength(1));
    expect(rows.single.valueJson, '{"v":2}');
    expect(rows.single.updatedAtMs, 2);

    await store.clearImplicitData();
    expect(await store.loadImplicitData(), isEmpty);
  });

  test(
    'history event upsert preserves ordering and repeated id updates',
    () async {
      await store.upsertComic(
        const ComicRecord(
          id: 'comic-h1',
          title: 'History Comic',
          normalizedTitle: 'history comic',
        ),
      );

      await store.upsertHistoryEvent(
        const HistoryEventRecord(
          id: 'evt-1',
          comicId: 'comic-h1',
          sourceTypeValue: 1,
          sourceKey: 'local',
          title: 'old',
          subtitle: 'sub',
          cover: 'cover',
          eventTime: '100',
          chapterIndex: 1,
          pageIndex: 1,
          readEpisode: 'ep-1',
        ),
      );
      await store.upsertHistoryEvent(
        const HistoryEventRecord(
          id: 'evt-1',
          comicId: 'comic-h1',
          sourceTypeValue: 1,
          sourceKey: 'local',
          title: 'new',
          subtitle: 'sub',
          cover: 'cover',
          eventTime: '200',
          chapterIndex: 2,
          pageIndex: 3,
          readEpisode: 'ep-2',
        ),
      );
      await store.upsertHistoryEvent(
        const HistoryEventRecord(
          id: 'evt-2',
          comicId: 'comic-h1',
          sourceTypeValue: 1,
          sourceKey: 'local',
          title: 'latest',
          subtitle: 'sub',
          cover: 'cover',
          eventTime: '300',
          chapterIndex: 0,
          pageIndex: 0,
          readEpisode: 'ep-3',
        ),
      );

      final latest = await store.loadLatestHistoryEvent('comic-h1');
      expect(latest, isNotNull);
      expect(latest?.id, 'evt-2');
      expect(latest?.eventTime, '300');

      final db = sqlite3.open(dbPath);
      addTearDown(db.dispose);
      final evt1Count =
          db.select('SELECT COUNT(*) AS c FROM history_events WHERE id = ?;', [
                'evt-1',
              ]).single['c']
              as int;
      expect(evt1Count, 1);
    },
  );

  test('deleteComicTitlesForComic removes only target comic titles', () async {
    await store.upsertComic(
      const ComicRecord(
        id: 'comic-delete-titles-a',
        title: 'Comic A',
        normalizedTitle: 'comic a',
      ),
    );
    await store.upsertComic(
      const ComicRecord(
        id: 'comic-delete-titles-b',
        title: 'Comic B',
        normalizedTitle: 'comic b',
      ),
    );

    await store.insertComicTitle(
      const ComicTitleRecord(
        comicId: 'comic-delete-titles-a',
        title: 'A',
        normalizedTitle: 'a',
        titleType: 'primary',
      ),
    );
    await store.insertComicTitle(
      const ComicTitleRecord(
        comicId: 'comic-delete-titles-b',
        title: 'B',
        normalizedTitle: 'b',
        titleType: 'primary',
      ),
    );

    await store.deleteComicTitlesForComic('comic-delete-titles-a');

    final db = sqlite3.open(dbPath);
    addTearDown(db.dispose);
    final targetCount =
        db.select(
              'SELECT COUNT(*) AS c FROM comic_titles WHERE comic_id = ?;',
              ['comic-delete-titles-a'],
            ).single['c']
            as int;
    final unrelatedCount =
        db.select(
              'SELECT COUNT(*) AS c FROM comic_titles WHERE comic_id = ?;',
              ['comic-delete-titles-b'],
            ).single['c']
            as int;
    expect(targetCount, 0);
    expect(unrelatedCount, 1);
  });

  test('deleteChaptersForComic preserves unrelated comics', () async {
    await store.upsertComic(
      const ComicRecord(
        id: 'comic-delete-chapter-a',
        title: 'Comic Chapter A',
        normalizedTitle: 'comic chapter a',
      ),
    );
    await store.upsertComic(
      const ComicRecord(
        id: 'comic-delete-chapter-b',
        title: 'Comic Chapter B',
        normalizedTitle: 'comic chapter b',
      ),
    );

    await store.upsertChapter(
      const ChapterRecord(
        id: 'chapter-delete-comic-a',
        comicId: 'comic-delete-chapter-a',
        title: 'Chapter A',
        normalizedTitle: 'chapter a',
      ),
    );
    await store.upsertChapter(
      const ChapterRecord(
        id: 'chapter-delete-comic-b',
        comicId: 'comic-delete-chapter-b',
        title: 'Chapter B',
        normalizedTitle: 'chapter b',
      ),
    );

    await store.deleteChaptersForComic('comic-delete-chapter-a');

    final db = sqlite3.open(dbPath);
    addTearDown(db.dispose);
    final targetCount =
        db.select('SELECT COUNT(*) AS c FROM chapters WHERE comic_id = ?;', [
              'comic-delete-chapter-a',
            ]).single['c']
            as int;
    final unrelatedCount =
        db.select('SELECT COUNT(*) AS c FROM chapters WHERE comic_id = ?;', [
              'comic-delete-chapter-b',
            ]).single['c']
            as int;
    expect(targetCount, 0);
    expect(unrelatedCount, 1);
  });

  test('deletePagesForChapter preserves unrelated chapters', () async {
    await store.upsertComic(
      const ComicRecord(
        id: 'comic-delete-pages-a',
        title: 'Comic Pages A',
        normalizedTitle: 'comic pages a',
      ),
    );
    await store.upsertComic(
      const ComicRecord(
        id: 'comic-delete-pages-b',
        title: 'Comic Pages B',
        normalizedTitle: 'comic pages b',
      ),
    );
    await store.upsertChapter(
      const ChapterRecord(
        id: 'chapter-delete-pages-a',
        comicId: 'comic-delete-pages-a',
        title: 'Chapter Pages A',
        normalizedTitle: 'chapter pages a',
      ),
    );
    await store.upsertChapter(
      const ChapterRecord(
        id: 'chapter-delete-pages-b',
        comicId: 'comic-delete-pages-b',
        title: 'Chapter Pages B',
        normalizedTitle: 'chapter pages b',
      ),
    );

    await store.upsertPage(
      const PageRecord(
        id: 'page-delete-chapter-a',
        chapterId: 'chapter-delete-pages-a',
        pageIndex: 0,
        localPath: '/tmp/page-delete-chapter-a.jpg',
      ),
    );
    await store.upsertPage(
      const PageRecord(
        id: 'page-delete-chapter-b',
        chapterId: 'chapter-delete-pages-b',
        pageIndex: 0,
        localPath: '/tmp/page-delete-chapter-b.jpg',
      ),
    );

    await store.deletePagesForChapter('chapter-delete-pages-a');

    final db = sqlite3.open(dbPath);
    addTearDown(db.dispose);
    final targetCount =
        db.select('SELECT COUNT(*) AS c FROM pages WHERE chapter_id = ?;', [
              'chapter-delete-pages-a',
            ]).single['c']
            as int;
    final unrelatedCount =
        db.select('SELECT COUNT(*) AS c FROM pages WHERE chapter_id = ?;', [
              'chapter-delete-pages-b',
            ]).single['c']
            as int;
    expect(targetCount, 0);
    expect(unrelatedCount, 1);
  });

  test('repeated upsertChapter is idempotent', () async {
    await store.upsertComic(
      const ComicRecord(
        id: 'comic-upsert-chapter-idempotent',
        title: 'Chapter Idempotent Comic',
        normalizedTitle: 'chapter idempotent comic',
      ),
    );

    const chapter = ChapterRecord(
      id: 'chapter-idempotent',
      comicId: 'comic-upsert-chapter-idempotent',
      chapterNo: 3,
      title: 'Chapter Three',
      normalizedTitle: 'chapter three',
    );
    await store.upsertChapter(chapter);
    await store.upsertChapter(chapter);

    final db = sqlite3.open(dbPath);
    addTearDown(db.dispose);
    final rows = db.select(
      '''
      SELECT id, comic_id, chapter_no, title, normalized_title
      FROM chapters
      WHERE id = ?;
    ''',
      [chapter.id],
    );
    expect(rows, hasLength(1));
    expect(rows.single['comic_id'], chapter.comicId);
    expect(rows.single['chapter_no'], chapter.chapterNo);
    expect(rows.single['title'], chapter.title);
    expect(rows.single['normalized_title'], chapter.normalizedTitle);
  });

  test('repeated upsertPage is idempotent', () async {
    await store.upsertComic(
      const ComicRecord(
        id: 'comic-upsert-page-idempotent',
        title: 'Page Idempotent Comic',
        normalizedTitle: 'page idempotent comic',
      ),
    );
    await store.upsertChapter(
      const ChapterRecord(
        id: 'chapter-upsert-page-idempotent',
        comicId: 'comic-upsert-page-idempotent',
        chapterNo: 7,
        title: 'Chapter Seven',
        normalizedTitle: 'chapter seven',
      ),
    );

    const page = PageRecord(
      id: 'page-idempotent',
      chapterId: 'chapter-upsert-page-idempotent',
      pageIndex: 2,
      localPath: '/tmp/page-idempotent.jpg',
      width: 1200,
      height: 1800,
      bytes: 456789,
    );
    await store.upsertPage(page);
    await store.upsertPage(page);

    final db = sqlite3.open(dbPath);
    addTearDown(db.dispose);
    final rows = db.select(
      '''
      SELECT id, chapter_id, page_index, local_path, width, height, bytes
      FROM pages
      WHERE id = ?;
    ''',
      [page.id],
    );
    expect(rows, hasLength(1));
    expect(rows.single['chapter_id'], page.chapterId);
    expect(rows.single['page_index'], page.pageIndex);
    expect(rows.single['local_path'], page.localPath);
    expect(rows.single['width'], page.width);
    expect(rows.single['height'], page.height);
    expect(rows.single['bytes'], page.bytes);
  });

  test(
    'chapter/page ordering remains stable after rebuild-style repeated writes',
    () async {
      await store.upsertComic(
        const ComicRecord(
          id: 'comic-rebuild-order',
          title: 'Rebuild Order Comic',
          normalizedTitle: 'rebuild order comic',
        ),
      );
      await store.upsertComic(
        const ComicRecord(
          id: 'comic-rebuild-order-unrelated',
          title: 'Unrelated Rebuild Comic',
          normalizedTitle: 'unrelated rebuild comic',
        ),
      );

      const chapterA = ChapterRecord(
        id: 'chapter-rebuild-a',
        comicId: 'comic-rebuild-order',
        chapterNo: 2,
        title: 'Chapter A',
        normalizedTitle: 'chapter a',
      );
      const chapterB = ChapterRecord(
        id: 'chapter-rebuild-b',
        comicId: 'comic-rebuild-order',
        chapterNo: 1,
        title: 'Chapter B',
        normalizedTitle: 'chapter b',
      );
      const unrelatedChapter = ChapterRecord(
        id: 'chapter-rebuild-unrelated',
        comicId: 'comic-rebuild-order-unrelated',
        chapterNo: 9,
        title: 'Unrelated Chapter',
        normalizedTitle: 'unrelated chapter',
      );
      await store.upsertChapter(chapterA);
      await store.upsertChapter(chapterB);
      await store.upsertChapter(unrelatedChapter);
      await store.upsertChapter(chapterA);
      await store.upsertChapter(chapterB);

      const pageA0 = PageRecord(
        id: 'page-rebuild-a0',
        chapterId: 'chapter-rebuild-a',
        pageIndex: 0,
        localPath: '/tmp/page-rebuild-a0.jpg',
      );
      const pageA1 = PageRecord(
        id: 'page-rebuild-a1',
        chapterId: 'chapter-rebuild-a',
        pageIndex: 1,
        localPath: '/tmp/page-rebuild-a1.jpg',
      );
      const pageB0 = PageRecord(
        id: 'page-rebuild-b0',
        chapterId: 'chapter-rebuild-b',
        pageIndex: 0,
        localPath: '/tmp/page-rebuild-b0.jpg',
      );
      const pageUnrelated = PageRecord(
        id: 'page-rebuild-unrelated',
        chapterId: 'chapter-rebuild-unrelated',
        pageIndex: 0,
        localPath: '/tmp/page-rebuild-unrelated.jpg',
      );
      await store.upsertPage(pageA0);
      await store.upsertPage(pageA1);
      await store.upsertPage(pageB0);
      await store.upsertPage(pageUnrelated);
      await store.upsertPage(pageA0);
      await store.upsertPage(pageA1);
      await store.upsertPage(pageB0);

      final primarySnapshot = await store.loadComicSnapshot(
        'comic-rebuild-order',
      );
      expect(primarySnapshot, isNotNull);
      expect(primarySnapshot!.chapters.map((chapter) => chapter.id).toList(), [
        'chapter-rebuild-b',
        'chapter-rebuild-a',
      ]);
      final chapterAInSnapshot = primarySnapshot.chapters.firstWhere(
        (chapter) => chapter.id == 'chapter-rebuild-a',
      );
      expect(chapterAInSnapshot.chapterNo, 2);

      final unrelatedSnapshot = await store.loadComicSnapshot(
        'comic-rebuild-order-unrelated',
      );
      expect(unrelatedSnapshot, isNotNull);
      expect(unrelatedSnapshot!.chapters.map((e) => e.id).toList(), [
        'chapter-rebuild-unrelated',
      ]);

      final db = sqlite3.open(dbPath);
      addTearDown(db.dispose);
      final chapterAPages = db.select(
        '''
        SELECT id
        FROM pages
        WHERE chapter_id = ?
        ORDER BY page_index ASC, id ASC;
        ''',
        ['chapter-rebuild-a'],
      );
      final unrelatedPages = db.select(
        '''
        SELECT id
        FROM pages
        WHERE chapter_id = ?
        ORDER BY page_index ASC, id ASC;
        ''',
        ['chapter-rebuild-unrelated'],
      );
      expect(chapterAPages.map((row) => row['id']).toList(), [
        'page-rebuild-a0',
        'page-rebuild-a1',
      ]);
      expect(unrelatedPages.map((row) => row['id']).toList(), [
        'page-rebuild-unrelated',
      ]);
    },
  );

  test(
    'cleanup delete sequence rolls back atomically on mid-sequence failure',
    () async {
      await store.upsertComic(
        const ComicRecord(
          id: 'rollback-comic',
          title: 'Rollback Comic',
          normalizedTitle: 'rollback comic',
        ),
      );
      await store.upsertChapter(
        const ChapterRecord(
          id: 'rollback-chapter',
          comicId: 'rollback-comic',
          title: 'Rollback Chapter',
          normalizedTitle: 'rollback chapter',
        ),
      );
      await store.upsertPage(
        const PageRecord(
          id: 'rollback-page',
          chapterId: 'rollback-chapter',
          pageIndex: 0,
          localPath: '/tmp/rollback-page.jpg',
        ),
      );

      await expectLater(
        AppDbHelper.instance.transaction(
          'test.cleanup.rollback',
          store,
          () async {
            await store.deletePagesForChapter('rollback-chapter');
            throw StateError('injected cleanup failure');
          },
        ),
        throwsStateError,
      );

      final db = sqlite3.open(dbPath);
      addTearDown(db.dispose);
      final chapterCount =
          db.select('SELECT COUNT(*) AS c FROM chapters WHERE id = ?;', [
                'rollback-chapter',
              ]).single['c']
              as int;
      final pageCount =
          db.select('SELECT COUNT(*) AS c FROM pages WHERE chapter_id = ?;', [
                'rollback-chapter',
              ]).single['c']
              as int;
      expect(chapterCount, 1);
      expect(pageCount, 1);
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

  test('deleteLocalLibraryItemById removes only targeted row', () async {
    await store.upsertComic(
      const ComicRecord(
        id: 'comic-delete-lli',
        title: 'Delete LLI',
        normalizedTitle: 'delete lli',
      ),
    );
    await store.upsertLocalLibraryItem(
      const LocalLibraryItemRecord(
        id: 'lli-1',
        comicId: 'comic-delete-lli',
        storageType: 'user_imported',
        localRootPath: '/library/delete-lli',
      ),
    );
    await store.upsertLocalLibraryItem(
      const LocalLibraryItemRecord(
        id: 'lli-2',
        comicId: 'comic-delete-lli',
        storageType: 'downloaded',
        localRootPath: '/library/delete-lli-2',
      ),
    );

    await store.deleteLocalLibraryItemById('lli-1');
    final snapshot = await store.loadComicSnapshot('comic-delete-lli');

    expect(snapshot, isNotNull);
    expect(snapshot!.localLibraryItems.map((e) => e.id).toList(), ['lli-2']);
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
    'legacy v2 database upgrades to v6 reader, remote match, cache, appdata, and repository schema',
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
          'cache_entries',
          'app_settings',
          'search_history',
          'implicit_data',
          'source_repositories',
          'source_packages',
        ]),
      );
      expect(await store.currentUserVersion(), store.schemaVersion);
    },
  );

  test('source repositories CRUD round-trip', () async {
    const record = SourceRepositoryRecord(
      id: 'repo_official',
      name: 'Official',
      indexUrl: 'https://example.com/index.json',
      enabled: true,
      userAdded: false,
      trustLevel: 'official',
      lastRefreshAtMs: 123,
      lastRefreshStatus: 'success',
      lastErrorCode: null,
      createdAtMs: 100,
      updatedAtMs: 200,
    );
    await store.upsertSourceRepository(record);

    final loaded = await store.loadSourceRepositoryById(record.id);
    expect(loaded, isNotNull);
    expect(loaded?.indexUrl, record.indexUrl);
    expect(loaded?.enabled, isTrue);
    expect(loaded?.trustLevel, 'official');

    await store.upsertSourceRepository(
      const SourceRepositoryRecord(
        id: 'repo_official',
        name: 'Official Updated',
        indexUrl: 'https://example.com/v2/index.json',
        enabled: false,
        userAdded: false,
        trustLevel: 'official',
        lastRefreshAtMs: 456,
        lastRefreshStatus: 'failed',
        lastErrorCode: 'network_failed',
        createdAtMs: 100,
        updatedAtMs: 500,
      ),
    );

    final all = await store.loadSourceRepositories();
    expect(all.length, 1);
    expect(all.single.name, 'Official Updated');
    expect(all.single.enabled, isFalse);
    expect(all.single.lastRefreshStatus, 'failed');
    expect(all.single.lastErrorCode, 'network_failed');

    await store.deleteSourceRepository('repo_official');
    expect(await store.loadSourceRepositoryById('repo_official'), isNull);
  });

  test('source packages replace and load are rebuildable', () async {
    await store.upsertSourceRepository(
      const SourceRepositoryRecord(
        id: 'repo_a',
        name: 'Repo A',
        indexUrl: 'https://example.com/index.json',
        enabled: true,
        userAdded: false,
        trustLevel: 'official',
        createdAtMs: 1,
        updatedAtMs: 1,
      ),
    );

    await store.replaceSourcePackagesForRepository(
      repositoryId: 'repo_a',
      records: const <SourcePackageRecord>[
        SourcePackageRecord(
          sourceKey: 'copy_manga',
          repositoryId: 'repo_a',
          name: 'Copy Manga',
          fileName: 'copy_manga.js',
          scriptUrl: 'https://example.com/copy_manga.js',
          availableVersion: '1.0.0',
          description: 'desc',
          lastSeenAtMs: 100,
        ),
      ],
    );

    final first = await store.loadSourcePackages(repositoryId: 'repo_a');
    expect(first.length, 1);
    expect(first.single.sourceKey, 'copy_manga');

    await store.replaceSourcePackagesForRepository(
      repositoryId: 'repo_a',
      records: const <SourcePackageRecord>[
        SourcePackageRecord(
          sourceKey: 'ehentai',
          repositoryId: 'repo_a',
          name: 'Eh',
          fileName: 'eh.js',
          availableVersion: '1.1.0',
          lastSeenAtMs: 200,
        ),
      ],
    );

    final second = await store.loadSourcePackages(repositoryId: 'repo_a');
    expect(second.length, 1);
    expect(second.single.sourceKey, 'ehentai');
    expect(second.single.availableVersion, '1.1.0');
  });

  test('favorite folder rename updates folder rows', () async {
    await store.upsertFavoriteFolder(
      const FavoriteFolderRecord(folderName: 'old-folder', orderValue: 0),
    );

    await store.renameFavoriteFolder(before: 'old-folder', after: 'new-folder');

    final raw = sqlite3.open(dbPath);
    addTearDown(raw.dispose);
    final folderRows = raw.select(
      'SELECT folder_name FROM favorite_folders ORDER BY folder_name ASC;',
    );
    expect(folderRows.map((row) => row['folder_name']), ['new-folder']);
  });

  test(
    'favorite folder order replacement keeps deterministic order values',
    () async {
      await store.upsertFavoriteFolder(
        const FavoriteFolderRecord(folderName: 'A', orderValue: 99),
      );
      await store.upsertFavoriteFolder(
        const FavoriteFolderRecord(folderName: 'B', orderValue: 99),
      );
      await store.upsertFavoriteFolder(
        const FavoriteFolderRecord(folderName: 'C', orderValue: 99),
      );

      await store.replaceFavoriteFolderOrder(const ['C', 'A', 'B']);

      final raw = sqlite3.open(dbPath);
      addTearDown(raw.dispose);
      final rows = raw.select(
        'SELECT folder_name, order_value FROM favorite_folders ORDER BY order_value ASC;',
      );
      expect(
        rows
            .map((row) => '${row['folder_name']}:${row['order_value']}')
            .toList(),
        ['C:0', 'A:1', 'B:2'],
      );
    },
  );

  test(
    'favorite folder delete and move-like item updates remain functional',
    () async {
      await store.upsertFavoriteFolder(
        const FavoriteFolderRecord(folderName: 'F1', orderValue: 0),
      );
      await store.upsertFavoriteFolder(
        const FavoriteFolderRecord(folderName: 'F2', orderValue: 1),
      );
      await store.upsertFavoriteFolderItem(
        const FavoriteFolderItemRecord(
          folderName: 'F1',
          comicId: 'comic-move',
          displayOrder: 0,
        ),
      );

      await store.deleteFavoriteFolderItem(
        folderName: 'F1',
        comicId: 'comic-move',
      );
      await store.upsertFavoriteFolderItem(
        const FavoriteFolderItemRecord(
          folderName: 'F2',
          comicId: 'comic-move',
          displayOrder: 0,
        ),
      );
      await store.deleteFavoriteFolder('F1');

      final raw = sqlite3.open(dbPath);
      addTearDown(raw.dispose);
      final folderRows = raw.select(
        'SELECT folder_name FROM favorite_folders ORDER BY folder_name ASC;',
      );
      final itemRows = raw.select(
        'SELECT folder_name, comic_id FROM favorite_folder_items ORDER BY comic_id ASC;',
      );
      expect(folderRows.map((row) => row['folder_name']), ['F2']);
      expect(
        itemRows.map((row) => '${row['folder_name']}:${row['comic_id']}'),
        ['F2:comic-move'],
      );
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

  test('eh tag taxonomy replace is rebuildable for same provider', () async {
    await store.replaceEhTagTaxonomyRecords(_ehentaiProvider, const [
      EhTagTaxonomyRecord(
        providerKey: _ehentaiProvider,
        locale: 'zh_CN',
        namespace: 'female',
        tagKey: 'glasses',
        translatedLabel: '眼镜',
        sourceSha: 'sha-1',
        sourceVersion: 1,
      ),
    ]);

    await store.replaceEhTagTaxonomyRecords(_ehentaiProvider, const [
      EhTagTaxonomyRecord(
        providerKey: _ehentaiProvider,
        locale: 'zh_CN',
        namespace: 'male',
        tagKey: 'tsundere',
        translatedLabel: '傲娇',
        sourceSha: 'sha-2',
        sourceVersion: 2,
      ),
    ]);

    final taxonomy = await store.loadEhTagTaxonomy(
      providerKey: _ehentaiProvider,
      locale: 'zh_CN',
    );

    expect(taxonomy.length, 1);
    expect(taxonomy.single.namespace, 'male');
    expect(taxonomy.single.tagKey, 'tsundere');
    expect(taxonomy.single.translatedLabel, '傲娇');
    expect(taxonomy.single.sourceSha, 'sha-2');
    expect(taxonomy.single.sourceVersion, 2);
  });

  test('eh tag taxonomy replace is atomic when insert fails', () async {
    await store.replaceEhTagTaxonomyRecords(_ehentaiProvider, const [
      EhTagTaxonomyRecord(
        providerKey: _ehentaiProvider,
        locale: 'zh_CN',
        namespace: 'female',
        tagKey: 'glasses',
        translatedLabel: '眼镜',
        sourceSha: 'sha-before',
        sourceVersion: 10,
      ),
    ]);

    await expectLater(
      store.replaceEhTagTaxonomyRecords(_ehentaiProvider, const [
        EhTagTaxonomyRecord(
          providerKey: _ehentaiProvider,
          locale: 'zh_CN',
          namespace: 'female',
          tagKey: 'duplicate',
          translatedLabel: '重复一',
        ),
        EhTagTaxonomyRecord(
          providerKey: _ehentaiProvider,
          locale: 'zh_CN',
          namespace: 'female',
          tagKey: 'duplicate',
          translatedLabel: '重复二',
        ),
      ]),
      throwsA(anything),
    );

    final taxonomy = await store.loadEhTagTaxonomy(
      providerKey: _ehentaiProvider,
      locale: 'zh_CN',
    );
    expect(taxonomy.length, 1);
    expect(taxonomy.single.tagKey, 'glasses');
    expect(taxonomy.single.sourceSha, 'sha-before');
    expect(taxonomy.single.sourceVersion, 10);
  });

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

  test('replacePageOrderItems is atomic when one insert fails', () async {
    await _insertReaderFixture(store);

    await expectLater(
      store.replacePageOrderItems('order-1', const [
        PageOrderItemRecord(
          pageOrderId: 'order-1',
          pageId: 'page-b',
          sortOrder: 0,
        ),
        PageOrderItemRecord(
          pageOrderId: 'order-1',
          pageId: 'missing-page',
          sortOrder: 1,
        ),
      ]),
      throwsA(
        predicate(
          (error) => error.toString().contains('FOREIGN KEY constraint failed'),
        ),
      ),
    );

    final pages = await store.loadActivePageOrderPages('chapter-1');
    expect(pages.map((page) => page.id), ['page-b', 'page-a']);
  });

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

  test(
    'saveReaderProgress rolls back session upsert when tab insert fails',
    () async {
      await store.upsertComic(
        const ComicRecord(
          id: 'session-comic-rollback',
          title: 'Session Comic Rollback',
          normalizedTitle: 'session comic rollback',
        ),
      );

      await expectLater(
        store.saveReaderProgress(
          session: const ReaderSessionRecord(
            id: 'session-rollback',
            comicId: 'session-comic-rollback',
          ),
          tab: const ReaderTabRecord(
            id: 'tab-rollback',
            sessionId: 'session-missing',
            comicId: 'session-comic-rollback',
            chapterId: 'chapter-rollback',
            pageIndex: 0,
            sourceRefJson: '{"id":"tab-rollback"}',
          ),
          makeActive: false,
        ),
        throwsA(
          predicate(
            (error) =>
                error.toString().contains('FOREIGN KEY constraint failed'),
          ),
        ),
      );

      final session = await store.loadReaderSessionByComic(
        'session-comic-rollback',
      );
      final tabs = await store.loadReaderTabsForSession('session-rollback');
      expect(session, isNull);
      expect(tabs, isEmpty);
    },
  );

  test(
    'saveReaderProgress returns skipped unchanged without extra mutation',
    () async {
      await store.upsertComic(
        const ComicRecord(
          id: 'session-comic-unchanged',
          title: 'Session Comic Unchanged',
          normalizedTitle: 'session comic unchanged',
        ),
      );
      UnifiedComicsStore.resetReaderSessionSaveDebugCounters();

      final firstResult = await store.saveReaderProgress(
        session: const ReaderSessionRecord(
          id: 'session-unchanged',
          comicId: 'session-comic-unchanged',
        ),
        tab: const ReaderTabRecord(
          id: 'tab-unchanged',
          sessionId: 'session-unchanged',
          comicId: 'session-comic-unchanged',
          chapterId: 'chapter-1',
          pageIndex: 3,
          sourceRefJson: '{"id":"tab-unchanged"}',
          pageOrderId: 'order-1',
        ),
        makeActive: true,
      );
      expect(firstResult.written, isTrue);

      final secondResult = await store.saveReaderProgress(
        session: const ReaderSessionRecord(
          id: 'session-unchanged',
          comicId: 'session-comic-unchanged',
        ),
        tab: const ReaderTabRecord(
          id: 'tab-unchanged',
          sessionId: 'session-unchanged',
          comicId: 'session-comic-unchanged',
          chapterId: 'chapter-1',
          pageIndex: 3,
          sourceRefJson: '{"id":"tab-unchanged"}',
          pageOrderId: 'order-1',
        ),
        makeActive: true,
      );
      final writeCounts =
          UnifiedComicsStore.readerSessionSaveDebugCountersSnapshot();

      expect(secondResult.written, isFalse);
      expect(secondResult.skipReason, ReaderSessionPersistSkipReason.unchanged);
      expect(writeCounts['sessionUpserts'], 1);
      expect(writeCounts['tabUpserts'], 1);
      expect(writeCounts['activeTabUpdates'], 1);
    },
  );

  test(
    'concurrent identical saveReaderProgress performs one real DB mutation',
    () async {
      await store.upsertComic(
        const ComicRecord(
          id: 'session-comic-concurrent',
          title: 'Session Comic Concurrent',
          normalizedTitle: 'session comic concurrent',
        ),
      );
      UnifiedComicsStore.resetReaderSessionSaveDebugCounters();

      final results = await Future.wait([
        store.saveReaderProgress(
          session: const ReaderSessionRecord(
            id: 'session-concurrent',
            comicId: 'session-comic-concurrent',
          ),
          tab: const ReaderTabRecord(
            id: 'tab-concurrent',
            sessionId: 'session-concurrent',
            comicId: 'session-comic-concurrent',
            chapterId: 'chapter-1',
            pageIndex: 3,
            sourceRefJson: '{"id":"tab-concurrent"}',
            pageOrderId: 'order-1',
          ),
          makeActive: true,
        ),
        store.saveReaderProgress(
          session: const ReaderSessionRecord(
            id: 'session-concurrent',
            comicId: 'session-comic-concurrent',
          ),
          tab: const ReaderTabRecord(
            id: 'tab-concurrent',
            sessionId: 'session-concurrent',
            comicId: 'session-comic-concurrent',
            chapterId: 'chapter-1',
            pageIndex: 3,
            sourceRefJson: '{"id":"tab-concurrent"}',
            pageOrderId: 'order-1',
          ),
          makeActive: true,
        ),
      ]);
      final writeCounts =
          UnifiedComicsStore.readerSessionSaveDebugCountersSnapshot();

      expect(results.first.written, isTrue);
      expect(results.last.written, isFalse);
      expect(results.last.skipReason, ReaderSessionPersistSkipReason.unchanged);
      expect(writeCounts['sessionUpserts'], 1);
      expect(writeCounts['tabUpserts'], 1);
      expect(writeCounts['activeTabUpdates'], 1);
    },
  );

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

  test(
    'repeated remote match upsert deterministically updates existing candidate',
    () async {
      await store.upsertComic(
        const ComicRecord(
          id: 'candidate-comic-2',
          title: 'Candidate Comic Two',
          normalizedTitle: 'candidate comic two',
        ),
      );
      await store.upsertSourcePlatform(
        const SourcePlatformRecord(
          id: 'ehentai',
          canonicalKey: 'ehentai',
          displayName: 'EHentai',
          kind: 'remote',
        ),
      );
      await store.upsertRemoteMatchCandidate(
        const RemoteMatchCandidateRecord(
          id: 'candidate-old',
          comicId: 'candidate-comic-2',
          sourcePlatformId: 'ehentai',
          sourceComicId: 'remote-2',
          sourceUrl: 'https://example.com/comic/remote-2',
          sourceTitle: 'Remote Two Original',
          confidence: 0.40,
          metadataJson: '{"pass":1}',
          status: 'pending',
          updatedAt: '2026-05-01 08:00:00',
        ),
      );
      await store.upsertRemoteMatchCandidate(
        const RemoteMatchCandidateRecord(
          id: 'candidate-new',
          comicId: 'candidate-comic-2',
          sourcePlatformId: 'ehentai',
          sourceComicId: 'remote-2',
          sourceUrl: 'https://example.com/comic/remote-2-updated',
          sourceTitle: 'Remote Two Updated',
          confidence: 0.91,
          metadataJson: '{"pass":2}',
          status: 'accepted',
          updatedAt: '2026-05-01 09:30:00',
        ),
      );

      final candidates = await store.loadRemoteMatchCandidates(
        'candidate-comic-2',
      );

      expect(candidates, hasLength(1));
      final candidate = candidates.single;
      expect(candidate.id, 'candidate-new');
      expect(candidate.sourceUrl, 'https://example.com/comic/remote-2-updated');
      expect(candidate.sourceTitle, 'Remote Two Updated');
      expect(candidate.confidence, 0.91);
      expect(candidate.metadataJson, '{"pass":2}');
      expect(candidate.status, 'accepted');
      expect(candidate.updatedAt, '2026-05-01 09:30:00');
    },
  );

  test(
    'deleteRemoteMatchCandidate removes only targeted candidate and preserves unrelated rows',
    () async {
      await store.upsertComic(
        const ComicRecord(
          id: 'candidate-comic-3',
          title: 'Candidate Comic Three',
          normalizedTitle: 'candidate comic three',
        ),
      );
      await store.upsertSourcePlatform(
        const SourcePlatformRecord(
          id: 'mangadex',
          canonicalKey: 'mangadex',
          displayName: 'MangaDex',
          kind: 'remote',
        ),
      );
      await store.upsertRemoteMatchCandidate(
        const RemoteMatchCandidateRecord(
          id: 'candidate-delete-me',
          comicId: 'candidate-comic-3',
          sourcePlatformId: 'mangadex',
          sourceComicId: 'remote-3-a',
          sourceUrl: 'https://example.com/comic/remote-3-a',
          sourceTitle: 'Delete Me',
          confidence: 0.72,
          metadataJson: '{"delete":true}',
          status: 'pending',
        ),
      );
      await store.upsertRemoteMatchCandidate(
        const RemoteMatchCandidateRecord(
          id: 'candidate-keep-1',
          comicId: 'candidate-comic-3',
          sourcePlatformId: 'mangadex',
          sourceComicId: 'remote-3-b',
          sourceUrl: 'https://example.com/comic/remote-3-b',
          sourceTitle: 'Keep One',
          confidence: 0.81,
          metadataJson: '{"keep":1}',
          status: 'pending',
        ),
      );
      await store.upsertRemoteMatchCandidate(
        const RemoteMatchCandidateRecord(
          id: 'candidate-keep-2',
          comicId: 'candidate-comic-3',
          sourcePlatformId: 'mangadex',
          sourceComicId: 'remote-3-c',
          sourceUrl: 'https://example.com/comic/remote-3-c',
          sourceTitle: 'Keep Two',
          confidence: 0.83,
          metadataJson: '{"keep":2}',
          status: 'accepted',
        ),
      );

      await store.deleteRemoteMatchCandidate('candidate-delete-me');

      final candidates = await store.loadRemoteMatchCandidates(
        'candidate-comic-3',
      );

      expect(candidates, hasLength(2));
      final ids = candidates.map((it) => it.id).toSet();
      expect(ids.contains('candidate-delete-me'), isFalse);
      expect(ids.contains('candidate-keep-1'), isTrue);
      expect(ids.contains('candidate-keep-2'), isTrue);
    },
  );
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
