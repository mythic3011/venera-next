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
        'comic_titles',
        'comics',
        'local_library_items',
        'source_platform_aliases',
        'source_platforms',
      ]),
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
    'comic snapshot readback includes titles and local library items',
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

      final snapshot = await store.loadComicSnapshot('comic-1');

      expect(snapshot, isNotNull);
      expect(snapshot?.comic.title, 'My Comic');
      expect(snapshot?.titles.map((title) => title.titleType).toList(), [
        'primary',
        'imported_filename',
      ]);
      expect(snapshot?.localLibraryItems.single.storageType, 'user_imported');
      expect(snapshot?.localLibraryItems.single.fileCount, 27);
    },
  );

  test('comic delete cascades into titles and local library items', () async {
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
    expect(titleCount, 0);
    expect(localCount, 0);
  });
}
