import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:venera/foundation/comic_type.dart';
import 'package:venera/foundation/db/unified_comics_store.dart';
import 'package:venera/foundation/diagnostics/diagnostics.dart';
import 'package:venera/foundation/favorites.dart';
import 'package:venera/foundation/local.dart';
import 'package:venera/utils/cbz.dart';
import 'package:venera/utils/import_comic.dart';
import 'package:venera/utils/import_failure.dart';
import 'package:venera/utils/local_import_storage.dart';
import 'package:venera/utils/translations.dart';

class _FakeImportStorage implements LocalImportStoragePort {
  Future<void> Function(String comicTitle)? onAssertReady;
  Future<bool> Function(String title)? onHasDuplicateTitle;
  Future<String> Function()? onRequireRootPath;
  Future<LocalImportPreflightDecision> Function(String comicTitle)?
  onPreflightImport;
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
  Future<LocalImportPreflightDecision> preflightImport(
    String comicTitle,
  ) async {
    final rootPath = await requireRootPath();
    final safeTitle = comicTitle.trim().replaceAll(
      RegExp(r'[<>:"/\\|?*\x00-\x1F]'),
      '_',
    );
    return await onPreflightImport?.call(comicTitle) ??
        LocalImportPreflightDecision(
          action: LocalImportPreflightAction.createNew,
          targetDirectory: '$rootPath/$safeTitle',
        );
  }

  @override
  Future<LocalComic> registerImportedComic(
    LocalComic comic, {
    String? existingComicId,
  }) async {
    registerCalls++;
    return await onRegisterImportedComic?.call(comic) ??
        LocalComic(
          id: existingComicId ?? 'canonical-1',
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
  TestWidgetsFlutterBinding.ensureInitialized();

  try {
    AppTranslation.translations;
  } catch (_) {
    AppTranslation.translations = {'en_US': <String, String>{}};
  }

  setUp(() {
    AppDiagnostics.configureSinksForTesting(const []);
  });

  tearDown(() {
    AppDiagnostics.resetForTesting();
  });

  test(
    'localDownloads source does not use legacyLocalComicsDirectory',
    () async {
      final content = await File('lib/utils/import_comic.dart').readAsString();
      expect(content.contains('legacyLocalComicsDirectory()'), isFalse);
    },
  );

  test('localDownloads source uses shallow non-followLinks listing', () async {
    final content = await File('lib/utils/import_comic.dart').readAsString();
    expect(content.contains('localDir.listSync('), isTrue);
    expect(content.contains('recursive: false'), isTrue);
    expect(content.contains('followLinks: false'), isTrue);
  });

  test(
    'localDownloads creates missing canonical root before scanning',
    () async {
      final content = await File('lib/utils/import_comic.dart').readAsString();
      expect(content.contains('localDir.createSync(recursive: true)'), isTrue);
    },
  );

  test(
    'localDownloads initializes local manager before resolving import root',
    () async {
      final content = await File('lib/utils/import_comic.dart').readAsString();
      expect(content.contains('LocalManager().ensureInitialized()'), isTrue);
    },
  );

  test(
    'localDownloads emits missingFiles when canonical root is not a directory',
    () async {
      final content = await File('lib/utils/import_comic.dart').readAsString();
      expect(content.contains('FileSystemEntity.typeSync('), isTrue);
      expect(content.contains('rootPath,'), isTrue);
      expect(content.contains('followLinks: false'), isTrue);
      expect(content.contains("message: 'import.local.missingFiles'"), isTrue);
    },
  );

  test('copy root helper creates parent directories recursively', () async {
    final tempRoot = await Directory.systemTemp.createTemp(
      'import-copy-root-recursive-',
    );
    addTearDown(() => tempRoot.delete(recursive: true));
    final nestedPath = '${tempRoot.path}/a/b/c/local';

    ensureImportCopyRootForTesting(nestedPath);

    expect(Directory(nestedPath).existsSync(), isTrue);
  });

  test(
    'cbz duplicate import throws ImportFailure and emits duplicateDetected without app.unhandled',
    () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'cbz-duplicate-detected',
      );
      addTearDown(() => tempRoot.delete(recursive: true));
      final cache = Directory('${tempRoot.path}/cache')..createSync();
      final extracted = Directory('${cache.path}/archive')..createSync();
      await _writeImageFile('${extracted.path}/page-1.png');
      final storage = _FakeImportStorage()
        ..onPreflightImport = (_) async => LocalImportPreflightDecision(
          action: LocalImportPreflightAction.conflictExistingCanonicalRecord,
          targetDirectory: '${tempRoot.path}/library',
          existingComicId: 'comic-1',
        );

      await expectLater(
        CBZ.importExtractedDirectoryForTesting(
          cache,
          extracted,
          fallbackTitle: 'duplicate-title',
          localImportStorage: storage,
        ),
        throwsA(isA<ImportFailure>()),
      );

      final importEvents = DevDiagnosticsApi.recent(channel: 'import.local');
      final duplicate = importEvents.firstWhere(
        (event) => event.message == 'import.local.duplicateDetected',
      );
      expect(duplicate.data['comicTitle'], 'duplicate-title');
      expect(duplicate.data['action'], 'blocked');
      expect(
        DevDiagnosticsApi.recent().any(
          (event) => event.message == 'app.unhandled',
        ),
        isFalse,
      );
      expect(storage.registerCalls, 0);
    },
  );

  test('cbz repair import reuses existing comic id', () async {
    final tempRoot = await Directory.systemTemp.createTemp('cbz-repair-');
    addTearDown(() => tempRoot.delete(recursive: true));
    final cache = Directory('${tempRoot.path}/cache')..createSync();
    final extracted = Directory('${cache.path}/archive')..createSync();
    await _writeImageFile('${extracted.path}/page-1.png');
    final storage = _FakeImportStorage()
      ..onPreflightImport = (_) async => LocalImportPreflightDecision(
        action: LocalImportPreflightAction.repairExisting,
        targetDirectory: '${tempRoot.path}/library/comic-a',
        existingComicId: 'comic-existing',
      );

    final comic = await CBZ.importExtractedDirectoryForTesting(
      cache,
      extracted,
      fallbackTitle: 'comic-a',
      localImportStorage: storage,
    );

    expect(comic.id, 'comic-existing');
    final events = DevDiagnosticsApi.recent(channel: 'import.local');
    expect(
      events.any((event) => event.message == 'import.local.repairStarted'),
      isTrue,
    );
    expect(
      events.any((event) => event.message == 'import.local.repairCompleted'),
      isTrue,
    );
  });

  test(
    'pdf duplicate import path uses ImportFailure.duplicateDetected',
    () async {
      final content = await File('lib/utils/import_comic.dart').readAsString();
      expect(content.contains('_importPdfAsComic'), isTrue);
      expect(
        content.contains('message: \'import.local.duplicateDetected\''),
        isTrue,
      );
      expect(content.contains('ImportFailure.duplicateDetected('), isTrue);
    },
  );

  test(
    'cbz import marks legacy mirror as policy-skip while canonical storage is available',
    () async {
      final storage = CanonicalLocalImportStorage(
        loadBrowseRecords: () async => <LocalLibraryBrowseRecord>[],
      );

      await CBZ.assertCanonicalStorageReadyForImport(
        'comic-a',
        storage: storage,
      );

      final events = DevDiagnosticsApi.recent(channel: 'import.local');
      expect(
        events.any(
          (event) => event.message == 'import.local.legacyMirrorSkipped',
        ),
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
    'legacy mirror skipped diagnostic does not block canonical duplicate check',
    () async {
      final storage = CanonicalLocalImportStorage(
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
    'default canonical storage does not call legacy migration mirror',
    () async {
      var legacyMirrorCalls = 0;
      final storage = CanonicalLocalImportStorage(
        loadBrowseRecords: () async => <LocalLibraryBrowseRecord>[],
        resolveRootPath: () async => '/library/local',
        hasCanonicalComicId: (_) async => false,
        syncComic: (_) async {},
        legacyMigrationMirror: (_, __) async {
          legacyMirrorCalls++;
        },
      );

      await storage.registerImportedComic(
        LocalComic(
          id: 'input-id',
          title: 'Comic A',
          subtitle: '',
          tags: const [],
          directory: 'comic-a',
          chapters: null,
          cover: 'cover.png',
          comicType: ComicType.local,
          downloadedChapters: const [],
          createdAt: DateTime.utc(2026, 5, 3),
        ),
      );

      expect(legacyMirrorCalls, 0);
    },
  );

  test(
    'canonical registration works when LocalManager storage is uninitialized',
    () async {
      final storage = CanonicalLocalImportStorage(
        loadBrowseRecords: () async => <LocalLibraryBrowseRecord>[],
        resolveRootPath: () async => '/library/local',
        hasCanonicalComicId: (_) async => false,
        syncComic: (_) async {},
      );

      await expectLater(
        storage.registerImportedComic(
          LocalComic(
            id: 'input-id',
            title: 'Comic A',
            subtitle: '',
            tags: const [],
            directory: 'comic-a',
            chapters: null,
            cover: 'cover.png',
            comicType: ComicType.local,
            downloadedChapters: const [],
            createdAt: DateTime.utc(2026, 5, 3),
          ),
        ),
        completes,
      );
    },
  );

  test('explicit legacy migration mirror is invoked when enabled', () async {
    var legacyMirrorCalls = 0;
    final storage = CanonicalLocalImportStorage(
      loadBrowseRecords: () async => <LocalLibraryBrowseRecord>[],
      resolveRootPath: () async => '/library/local',
      hasCanonicalComicId: (_) async => false,
      syncComic: (_) async {},
      enableLegacyMigrationMirror: true,
      legacyMigrationMirror: (comic, rootPath) async {
        legacyMirrorCalls++;
        expect(comic.title, 'Comic A');
        expect(rootPath, '/library/local');
      },
    );

    await storage.registerImportedComic(
      LocalComic(
        id: 'input-id',
        title: 'Comic A',
        subtitle: '',
        tags: const [],
        directory: 'comic-a',
        chapters: null,
        cover: 'cover.png',
        comicType: ComicType.local,
        downloadedChapters: const [],
        createdAt: DateTime.utc(2026, 5, 3),
      ),
    );

    expect(legacyMirrorCalls, 1);
  });

  test(
    'explicit legacy migration mirror failure emits legacyMirrorFailed',
    () async {
      final storage = CanonicalLocalImportStorage(
        loadBrowseRecords: () async => <LocalLibraryBrowseRecord>[],
        resolveRootPath: () async => '/library/local',
        hasCanonicalComicId: (_) async => false,
        syncComic: (_) async {},
        enableLegacyMigrationMirror: true,
        legacyMigrationMirror: (_, __) async {
          throw StateError('mirror failed');
        },
      );

      await storage.registerImportedComic(
        LocalComic(
          id: 'input-id',
          title: 'Comic A',
          subtitle: '',
          tags: const [],
          directory: 'comic-a',
          chapters: null,
          cover: 'cover.png',
          comicType: ComicType.local,
          downloadedChapters: const [],
          createdAt: DateTime.utc(2026, 5, 3),
        ),
      );

      final events = DevDiagnosticsApi.recent(channel: 'import.local');
      expect(
        events.any(
          (event) => event.message == 'import.local.legacyMirrorFailed',
        ),
        isTrue,
      );
    },
  );

  test('import_comic does not reference legacyRegisterLocalComic', () async {
    final content = await File('lib/utils/import_comic.dart').readAsString();
    expect(content.contains('legacyRegisterLocalComic'), isFalse);
  });

  test(
    'import_comic does not enable legacy migration mirror by default',
    () async {
      final content = await File('lib/utils/import_comic.dart').readAsString();
      expect(content.contains('enableLegacyMigrationMirror: true'), isFalse);
    },
  );

  test('local_import_storage default path has no LocalManager usage', () async {
    final content = await File(
      'lib/utils/local_import_storage.dart',
    ).readAsString();
    expect(content.contains('LocalManager('), isFalse);
    expect(content.contains('legacyRegisterLocalComic'), isFalse);
  });

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

  test(
    'registerComics creates missing canonical local root before copy',
    () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'import-local-root-missing',
      );
      addTearDown(() => tempRoot.delete(recursive: true));

      final sourceDir = Directory('${tempRoot.path}/source/comic-a')
        ..createSync(recursive: true);
      await _writeImageFile('${sourceDir.path}/cover.png');

      final localRoot = '${tempRoot.path}/runtimeRoot/local';
      final storage = _FakeImportStorage();
      storage.onRequireRootPath = () async => localRoot;
      storage.onRegisterImportedComic = (comic) async => comic;

      final importer = ImportComic(
        localImportStorage: storage,
        copyToLocal: true,
      );

      final success = await importer.registerComics({
        null: [
          LocalComic(
            id: '0',
            title: 'Comic A',
            subtitle: '',
            tags: const [],
            directory: sourceDir.path,
            chapters: null,
            cover: 'cover.png',
            comicType: ComicType.local,
            downloadedChapters: const [],
            createdAt: DateTime.utc(2026, 5, 3),
          ),
        ],
      }, true);

      expect(success, isTrue);
      expect(Directory(localRoot).existsSync(), isTrue);
      expect(File('$localRoot/comic-a/cover.png').existsSync(), isTrue);
    },
  );

  test(
    'registerComics fails when copy path throws and emits import.local.copyFailed',
    () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'import-copy-failed',
      );
      addTearDown(() => tempRoot.delete(recursive: true));

      final localRoot = '${tempRoot.path}/runtimeRoot/local';
      final storage = _FakeImportStorage();
      storage.onRequireRootPath = () async => localRoot;
      storage.onRegisterImportedComic = (comic) async => comic;

      final importer = ImportComic(
        localImportStorage: storage,
        copyToLocal: true,
      );

      final success = await importer.registerComics({
        null: [
          LocalComic(
            id: '0',
            title: 'Comic A',
            subtitle: '',
            tags: const [],
            directory: '${tempRoot.path}/does-not-exist/comic-a',
            chapters: null,
            cover: 'cover.png',
            comicType: ComicType.local,
            downloadedChapters: const [],
            createdAt: DateTime.utc(2026, 5, 3),
          ),
        ],
      }, true);

      expect(success, isFalse);
      expect(storage.registerCalls, 0);

      final events = DevDiagnosticsApi.recent(channel: 'import.local');
      final copyFailedEvent = events.firstWhere(
        (event) => event.message == 'import.local.copyFailed',
      );
      expect(copyFailedEvent.data['destinationRoot'], localRoot);
      expect(copyFailedEvent.data['sourcePaths'], [
        '${tempRoot.path}/does-not-exist/comic-a',
      ]);
      expect(copyFailedEvent.data['errorType'], isNotEmpty);

      final lifecycleEvents = DevDiagnosticsApi.recent(
        channel: 'import.lifecycle',
      );
      final started = lifecycleEvents.firstWhere(
        (event) => event.message == 'import.lifecycle.started',
      );
      expect(started.data['operation'], 'import.register_comics');
      expect(
        lifecycleEvents.any(
          (event) =>
              event.message == 'import.lifecycle.phase' &&
              event.data['phase'] == 'copy_to_local.started',
        ),
        isTrue,
      );
      final failed = lifecycleEvents.firstWhere(
        (event) => event.message == 'import.lifecycle.failed',
      );
      expect(failed.data['importId'], started.data['importId']);
      expect(failed.data['phase'], 'register');
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
    'cbz import fails closed when destination folder already exists',
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
      final storage = _FakeImportStorage()
        ..onRequireRootPath = () async {
          return localRoot.path;
        }
        ..onPreflightImport = (_) async => LocalImportPreflightDecision(
          action: LocalImportPreflightAction.conflictExistingDirectory,
          targetDirectory: existingDir.path,
        );
      File('${existingDir.path}/old.txt').writeAsStringSync('existing');
      await _writeImageFile('${extracted.path}/page-1.png');

      await expectLater(
        CBZ.importExtractedDirectoryForTesting(
          cache,
          extracted,
          fallbackTitle: 'collision-title',
          localImportStorage: storage,
        ),
        throwsA(isA<ImportFailure>()),
      );
      expect(
        File('${existingDir.path}/old.txt').readAsStringSync(),
        'existing',
      );
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
