import 'package:flutter_test/flutter_test.dart';
import 'package:venera/foundation/comic_type.dart';
import 'package:venera/foundation/db/unified_comics_store.dart';
import 'package:venera/foundation/diagnostics/diagnostics.dart';
import 'package:venera/foundation/favorites.dart';
import 'package:venera/foundation/local.dart';
import 'package:venera/foundation/local_comics_legacy_bridge.dart';
import 'package:venera/utils/cbz.dart';
import 'package:venera/utils/import_comic.dart';
import 'package:venera/utils/local_import_storage.dart';

class _FakeImportStorage implements LocalImportStoragePort {
  Future<void> Function(String comicTitle)? onAssertReady;
  Future<bool> Function(String title)? onHasDuplicateTitle;
  Future<String> Function()? onRequireRootPath;
  Future<LocalComic> Function(LocalComic comic)? onRegisterImportedComic;

  int hasDuplicateCalls = 0;
  int registerCalls = 0;

  @override
  Future<void> assertStorageReadyForImport(String comicTitle) async {
    await onAssertReady?.call(comicTitle);
  }

  @override
  Future<bool> hasDuplicateTitle(String title) async {
    hasDuplicateCalls++;
    return await onHasDuplicateTitle?.call(title) ?? false;
  }

  @override
  Future<String> requireRootPath() async {
    return await onRequireRootPath?.call() ?? '/library/local';
  }

  @override
  Future<LocalComic> registerImportedComic(LocalComic comic) async {
    registerCalls++;
    return await onRegisterImportedComic?.call(comic) ??
        LocalComic(
          id: 'canonical-1',
          title: comic.title,
          subtitle: comic.subtitle,
          tags: comic.tags,
          directory: comic.directory,
          chapters: comic.chapters,
          cover: comic.cover,
          comicType: comic.comicType,
          downloadedChapters: comic.downloadedChapters,
          createdAt: comic.createdAt,
        );
  }
}

void main() {
  setUp(() {
    AppDiagnostics.configureSinksForTesting(const []);
  });

  tearDown(() {
    AppDiagnostics.resetForTesting();
  });

  test(
    'cbz import does not require legacy local comics db when canonical storage is available',
    () async {
      final storage = CanonicalLocalImportStorage(
        legacyLookup: (_) => const LegacyLocalComicLookupUnavailable(),
        loadBrowseRecords: () async => <LocalLibraryBrowseRecord>[],
      );

      await CBZ.assertCanonicalStorageReadyForImport(
        'comic-a',
        storage: storage,
      );

      final events = DevDiagnosticsApi.recent(channel: 'import.local');
      expect(
        events.any((event) => event.message == 'import.local.legacyBlocked'),
        isTrue,
      );
      expect(
        events.any((event) => event.message == 'import.local.canonicalReady'),
        isTrue,
      );
    },
  );

  test('canonical local storage unavailable fails closed', () async {
    final storage = CanonicalLocalImportStorage(
      loadBrowseRecords: () async => throw StateError('db unavailable'),
    );

    await expectLater(
      CBZ.assertCanonicalStorageReadyForImport('comic-a', storage: storage),
      throwsA(
        predicate<Object>(
          (error) => error.toString().contains('CANONICAL_UNAVAILABLE'),
        ),
      ),
    );
  });

  test(
    'legacy lookup unavailable does not fail import before canonical duplicate check',
    () async {
      final storage = CanonicalLocalImportStorage(
        legacyLookup: (_) => const LegacyLocalComicLookupUnavailable(),
        loadBrowseRecords: () async => const <LocalLibraryBrowseRecord>[
          LocalLibraryBrowseRecord(
            comicId: 'comic-1',
            title: 'Comic A',
            normalizedTitle: 'comic a',
            storageType: 'user_imported',
            importedAt: null,
            updatedAt: null,
            userTags: <String>[],
            sourceTags: <String>[],
          ),
        ],
      );

      await storage.assertStorageReadyForImport('Comic A');
      final isDuplicate = await storage.hasDuplicateTitle('Comic A');

      expect(isDuplicate, isTrue);
    },
  );

  test(
    'registerComics writes through canonical local import storage',
    () async {
      final storage = _FakeImportStorage();
      final favorites = <FavoriteItem>[];
      final importedCount = await registerImportedComicsForTesting(
        importedComics: {
          'folder-a': [
            LocalComic(
              id: '0',
              title: 'Comic A',
              subtitle: 'Author',
              tags: const ['tag:a'],
              directory: '/tmp/comic-a',
              chapters: null,
              cover: 'cover.png',
              comicType: ComicType.local,
              downloadedChapters: const [],
              createdAt: DateTime.utc(2026, 5, 3),
            ),
          ],
        },
        localImportStorage: storage,
        copyComicsToLocalDir: (comics) async => comics,
        addFavoriteComic: (_, item) => favorites.add(item),
        copy: false,
      );

      expect(importedCount, 1);
      expect(storage.registerCalls, 1);
      expect(favorites.single.id, 'canonical-1');
    },
  );
}
