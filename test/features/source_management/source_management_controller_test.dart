import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:venera/features/sources/comic_source/comic_source.dart';
import 'package:venera/features/sources/comic_source/source_management_controller.dart';
import 'package:venera/foundation/app.dart';
import 'package:venera/foundation/appdata.dart';
import 'package:venera/foundation/db/unified_comics_store.dart';
import 'package:venera/foundation/source_identity/source_identity.dart';
import 'package:venera/utils/io.dart';

ComicSource _fakeSource(String key, {String version = '1.0.0'}) {
  return ComicSource(
    'Fake Source',
    key,
    null,
    null,
    null,
    null,
    const [],
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    '/tmp/$key.js',
    'https://example.com/$key',
    version,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    false,
    false,
    null,
    null,
    identity: sourceIdentityFromKey(key, names: const ['Fake Source']),
  );
}

void main() {
  group('SourceManagementController command routing', () {
    late Directory tempDir;
    late bool hadOldCachePath;
    String? oldCachePath;
    late String oldSourceListUrl;
    UnifiedComicsStore? repositoryStore;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync(
        'source-management-controller-test-',
      );
      try {
        oldCachePath = App.cachePath;
        hadOldCachePath = true;
      } catch (_) {
        oldCachePath = null;
        hadOldCachePath = false;
      }
      App.cachePath = tempDir.path;
      oldSourceListUrl = appdata.settings['comicSourceListUrl'] as String;
      appdata.settings['comicSourceListUrl'] =
          'https://example.com/legacy-index.json';
    });

    tearDown(() async {
      appdata.settings['comicSourceListUrl'] = oldSourceListUrl;
      if (repositoryStore != null) {
        await repositoryStore!.close();
        repositoryStore = null;
      }
      if (hadOldCachePath) {
        App.cachePath = oldCachePath!;
      } else {
        // Keep cachePath initialized to a valid temp location for follow-up tests.
        final fallback = Directory.systemTemp.createTempSync(
          'source-management-cache-fallback-',
        );
        App.cachePath = fallback.path;
      }
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('addSourceFromUrl routes fetched script and filename to installer', () async {
      String? fetchedUrl;
      String? installedJs;
      String? installedFilename;
      final controller = SourceManagementController(
        fetchText: (url) async {
          fetchedUrl = url;
          return '/* source */';
        },
        installSourceFromJs: (js, fileName) async {
          installedJs = js;
          installedFilename = fileName;
        },
      );

      await controller.addSourceFromUrl('https://example.com/sources/copymanga.js');

      expect(fetchedUrl, 'https://example.com/sources/copymanga.js');
      expect(installedJs, '/* source */');
      expect(installedFilename, 'copymanga.js');
    });

    test('addSourceFromConfigFile returns when picker yields null', () async {
      var installCalls = 0;
      final controller = SourceManagementController(
        pickJsConfigFile: () async => null,
        installSourceFromJs: (_, __) async {
          installCalls++;
        },
      );

      await controller.addSourceFromConfigFile();

      expect(installCalls, 0);
    });

    test('addSourceFromConfigFile routes selected file content to installer', () async {
      final file = File(FilePath.join(tempDir.path, 'custom_source.js'));
      file.writeAsStringSync('/* custom source */');

      String? installedJs;
      String? installedFilename;
      final controller = SourceManagementController(
        pickJsConfigFile: () async => FileSelectResult(file.path),
        installSourceFromJs: (js, fileName) async {
          installedJs = js;
          installedFilename = fileName;
        },
      );

      await controller.addSourceFromConfigFile();

      expect(installedJs, '/* custom source */');
      expect(installedFilename, 'custom_source.js');
    });

    test('checkUpdates returns zero and skips fetch when no installed sources', () async {
      var fetchCalls = 0;
      final controller = SourceManagementController(
        fetchText: (_) async {
          fetchCalls++;
          return '[]';
        },
      );

      final count = await controller.checkUpdates();
      expect(count, 0);
      expect(fetchCalls, 0);
    });

    test('checkUpdates computes update count from repository payload', () async {
      final source = _fakeSource('m26-source-a', version: '1.0.0');
      final manager = ComicSourceManager();
      manager.add(source);
      addTearDown(() => manager.remove(source.key));

      final controller = SourceManagementController(
        fetchText: (_) async => jsonEncode(<Map<String, Object?>>[
          <String, Object?>{'key': source.key, 'version': '1.1.0'},
        ]),
      );

      final count = await controller.checkUpdates();
      expect(count, 1);
      expect(manager.availableUpdates[source.key], '1.1.0');
    });

    test('checkUpdates supports object payload with packages array', () async {
      final source = _fakeSource('m26-source-b', version: '2.0.0');
      final manager = ComicSourceManager();
      manager.add(source);
      addTearDown(() => manager.remove(source.key));

      final controller = SourceManagementController(
        fetchText: (_) async => jsonEncode(<String, Object?>{
          'packages': <Map<String, Object?>>[
            <String, Object?>{'key': source.key, 'version': '2.1.0'},
          ],
        }),
      );

      final count = await controller.checkUpdates();
      expect(count, 1);
      expect(manager.availableUpdates[source.key], '2.1.0');
    });

    test('listRepositories seeds from legacy comicSourceListUrl when empty', () async {
      repositoryStore = UnifiedComicsStore('${tempDir.path}/source_registry.db');
      await repositoryStore!.init();
      final controller = SourceManagementController(
        repositoryStoreProvider: () => repositoryStore,
      );

      final repos = await controller.listRepositories();

      expect(repos.length, 1);
      expect(repos.single.indexUrl, 'https://example.com/legacy-index.json');
      expect(repos.single.userAdded, isFalse);
      expect(repos.single.trustLevel, 'official');
    });

    test('addRepository inserts and listRepositories returns it', () async {
      repositoryStore = UnifiedComicsStore('${tempDir.path}/source_registry.db');
      await repositoryStore!.init();
      final controller = SourceManagementController(
        repositoryStoreProvider: () => repositoryStore,
      );

      await controller.addRepository(
        'https://repo.example.com/index.json',
        name: 'Repo Example',
      );
      final repos = await controller.listRepositories();

      expect(repos.any((repo) => repo.name == 'Repo Example'), isTrue);
      expect(
        repos.any((repo) => repo.indexUrl == 'https://repo.example.com/index.json'),
        isTrue,
      );
    });

    test('refreshRepository success updates last refresh status', () async {
      repositoryStore = UnifiedComicsStore('${tempDir.path}/source_registry.db');
      await repositoryStore!.init();
      final controller = SourceManagementController(
        repositoryStoreProvider: () => repositoryStore,
        fetchText: (_) async => jsonEncode(<String, Object?>{
          'sources': <Map<String, Object?>>[
            <String, Object?>{'key': 's1', 'version': '1.0.1'},
          ],
        }),
      );
      final repo = await controller.addRepository(
        'https://repo-success.example.com/index.json',
      );

      final count = await controller.refreshRepository(repo.id);
      final rows = await controller.listRepositories();
      final refreshed = rows.firstWhere((r) => r.id == repo.id);

      expect(count, 1);
      expect(refreshed.lastRefreshStatus, 'success');
      expect(refreshed.lastErrorCode, isNull);
      expect(refreshed.lastRefreshAtMs, isNotNull);

      final packages = await controller.listAvailablePackages(
        repositoryId: repo.id,
      );
      expect(packages.length, 1);
      expect(packages.single.sourceKey, 's1');
    });

    test('refreshRepository failure keeps repository and records failed status', () async {
      repositoryStore = UnifiedComicsStore('${tempDir.path}/source_registry.db');
      await repositoryStore!.init();
      final controller = SourceManagementController(
        repositoryStoreProvider: () => repositoryStore,
        fetchText: (_) async => throw Exception('network failed'),
      );
      final repo = await controller.addRepository(
        'https://repo-failed.example.com/index.json',
      );

      await expectLater(
        controller.refreshRepository(repo.id),
        throwsException,
      );

      final refreshed = await repositoryStore!.loadSourceRepositoryById(repo.id);
      expect(refreshed, isNotNull);
      expect(refreshed?.lastRefreshStatus, 'failed');
      expect(refreshed?.lastErrorCode, 'repository_refresh_failed');
    });

    test('unsupported repository schema version returns typed error code', () async {
      repositoryStore = UnifiedComicsStore('${tempDir.path}/source_registry.db');
      await repositoryStore!.init();
      final controller = SourceManagementController(
        repositoryStoreProvider: () => repositoryStore,
        fetchText: (_) async => jsonEncode(<String, Object?>{
          'schemaVersion': 2,
          'sources': <Map<String, Object?>>[],
        }),
      );
      final repo = await controller.addRepository(
        'https://repo-schema.example.com/index.json',
      );

      await expectLater(
        controller.refreshRepository(repo.id),
        throwsA(isA<SourceRepositoryIndexException>()),
      );
      final refreshed = await repositoryStore!.loadSourceRepositoryById(repo.id);
      expect(refreshed?.lastErrorCode, 'REPOSITORY_SCHEMA_UNSUPPORTED');
    });

    test('repository package url escaping base path is rejected', () async {
      repositoryStore = UnifiedComicsStore('${tempDir.path}/source_registry.db');
      await repositoryStore!.init();
      final controller = SourceManagementController(
        repositoryStoreProvider: () => repositoryStore,
        fetchText: (_) async => jsonEncode(<String, Object?>{
          'sources': <Map<String, Object?>>[
            <String, Object?>{
              'key': 's1',
              'name': 'Source 1',
              'fileName': '../escape.js',
              'version': '1.0.0',
            },
          ],
        }),
      );
      final repo = await controller.addRepository(
        'https://repo-escape.example.com/path/index.json',
      );

      await expectLater(
        controller.refreshRepository(repo.id),
        throwsA(isA<SourceRepositoryIndexException>()),
      );
      final refreshed = await repositoryStore!.loadSourceRepositoryById(repo.id);
      expect(refreshed?.lastErrorCode, 'REPOSITORY_PACKAGE_URL_INVALID');
    });

    test('refreshRepository failure does not wipe previous package cache', () async {
      repositoryStore = UnifiedComicsStore('${tempDir.path}/source_registry.db');
      await repositoryStore!.init();
      var shouldFail = false;
      final controller = SourceManagementController(
        repositoryStoreProvider: () => repositoryStore,
        fetchText: (_) async {
          if (shouldFail) {
            throw Exception('network failed');
          }
          return jsonEncode(<String, Object?>{
            'sources': <Map<String, Object?>>[
              <String, Object?>{
                'key': 'cached_source',
                'name': 'Cached Source',
                'fileName': 'cached_source.js',
                'version': '1.0.0',
              },
            ],
          });
        },
      );
      final repo = await controller.addRepository(
        'https://repo-cache.example.com/index.json',
      );

      final successCount = await controller.refreshRepository(repo.id);
      expect(successCount, 1);

      shouldFail = true;
      await expectLater(
        controller.refreshRepository(repo.id),
        throwsException,
      );
      final packages = await controller.listAvailablePackages(
        repositoryId: repo.id,
      );
      expect(packages.length, 1);
      expect(packages.single.sourceKey, 'cached_source');
    });

    test('refreshRepository is serialized per repository', () async {
      repositoryStore = UnifiedComicsStore('${tempDir.path}/source_registry.db');
      await repositoryStore!.init();
      var inFlight = 0;
      var maxInFlight = 0;
      var fetchCalls = 0;
      final firstFetchStarted = Completer<void>();
      final releaseFirstFetch = Completer<void>();
      final controller = SourceManagementController(
        repositoryStoreProvider: () => repositoryStore,
        fetchText: (_) async {
          fetchCalls++;
          inFlight++;
          maxInFlight = max(maxInFlight, inFlight);
          try {
            if (fetchCalls == 1) {
              firstFetchStarted.complete();
              await releaseFirstFetch.future;
            }
            return jsonEncode(<String, Object?>{
              'sources': <Map<String, Object?>>[
                <String, Object?>{
                  'key': 'serialized_source',
                  'name': 'Serialized Source',
                  'fileName': 'serialized_source.js',
                  'version': '1.0.$fetchCalls',
                },
              ],
            });
          } finally {
            inFlight--;
          }
        },
      );
      final repo = await controller.addRepository(
        'https://repo-serialized.example.com/index.json',
      );
      final first = controller.refreshRepository(repo.id);
      await firstFetchStarted.future;
      final second = controller.refreshRepository(repo.id);
      await Future<void>.delayed(Duration.zero);
      expect(maxInFlight, 1);
      releaseFirstFetch.complete();
      await Future.wait(<Future<int>>[first, second]);

      expect(maxInFlight, 1);
      expect(fetchCalls, 2);
      final packages = await controller.listAvailablePackages(
        repositoryId: repo.id,
      );
      expect(packages.length, 1);
      expect(packages.single.sourceKey, 'serialized_source');
      final refreshed = await repositoryStore!.loadSourceRepositoryById(repo.id);
      expect(refreshed?.lastRefreshStatus, 'success');
    });
  });
}
