import 'dart:convert';
import 'dart:io';

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

const _singlePixelPngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO0p6xQAAAAASUVORK5CYII=';

Future<File> _writeImageFile(String path) {
  return File(path).writeAsBytes(base64Decode(_singlePixelPngBase64));
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

  test('cbz import keeps single cover image as first page', () async {
    final tempRoot = await Directory.systemTemp.createTemp('cbz-import-cover');
    addTearDown(() => tempRoot.delete(recursive: true));
    final cache = Directory('${tempRoot.path}/cache')..createSync();
    final extracted = Directory('${cache.path}/archive')..createSync();
    final localRoot = Directory('${tempRoot.path}/library')..createSync();
    await _writeImageFile('${extracted.path}/cover.png');

    final comic = await CBZ.importExtractedDirectoryForTesting(
      cache,
      extracted,
      fallbackTitle: 'single-cover',
      localImportStorage: _FakeImportStorage()
        ..onRequireRootPath = () async => localRoot.path,
    );

    final importedDir = Directory('${localRoot.path}/${comic.directory}');
    expect(File('${importedDir.path}/cover.png').existsSync(), isTrue);
    expect(File('${importedDir.path}/1.png').existsSync(), isTrue);
  });

  test(
    'cbz import resolves destination folder collision when folder exists but db has no duplicate',
    () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'cbz-import-collision',
      );
      addTearDown(() => tempRoot.delete(recursive: true));
      final cache = Directory('${tempRoot.path}/cache')..createSync();
      final extracted = Directory('${cache.path}/archive')..createSync();
      final localRoot = Directory('${tempRoot.path}/library')..createSync();
      final existingDir = Directory('${localRoot.path}/collision-title')
        ..createSync();
      File('${existingDir.path}/old.txt').writeAsStringSync('existing');
      await _writeImageFile('${extracted.path}/page-1.png');

      final comic = await CBZ.importExtractedDirectoryForTesting(
        cache,
        extracted,
        fallbackTitle: 'collision-title',
        localImportStorage: _FakeImportStorage()
          ..onRequireRootPath = () async => localRoot.path,
      );

      expect(comic.directory, isNot('collision-title'));
      expect(
        Directory('${localRoot.path}/${comic.directory}').existsSync(),
        isTrue,
      );
      expect(File('${existingDir.path}/old.txt').readAsStringSync(), 'existing');
    },
  );

  test('cbz import cleans import cache when import fails', () async {
    final tempRoot = await Directory.systemTemp.createTemp('cbz-import-cache');
    addTearDown(() => tempRoot.delete(recursive: true));
    final cache = Directory('${tempRoot.path}/cache')..createSync();
    File('${cache.path}/leftover.txt').writeAsStringSync('leftover');

    await expectLater(
      CBZ.runWithImportCacheCleanupForTesting(cache, () async {
        throw StateError('boom');
      }),
      throwsA(isA<StateError>()),
    );
    expect(cache.existsSync(), isFalse);
  });
}
