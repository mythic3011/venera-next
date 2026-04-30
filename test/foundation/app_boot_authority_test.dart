import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:venera/foundation/app.dart';
import 'package:venera/foundation/db/unified_comics_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const appChannel = MethodChannel('venera/method_channel');
  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

  Future<void> mockPathProvider(Directory dir) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (call) async {
          if (call.method == 'getApplicationSupportDirectory' ||
              call.method == 'getApplicationDocumentsDirectory' ||
              call.method == 'getApplicationCacheDirectory') {
            return dir.path;
          }
          return dir.path;
        });
  }

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(appChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);
  });

  test('runtime component init does not open legacy runtime stores', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'app-boot-authority-',
    );
    addTearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    final store = UnifiedComicsStore(p.join(tempDir.path, 'data', 'venera.db'));
    addTearDown(store.close);

    await App.initRuntimeComponents(
      initAppData: () async {},
      canonicalStore: store,
      initCanonicalStore: store.init,
      seedSourcePlatforms: store.seedDefaultSourcePlatforms,
    );

    expect(
      File(p.join(tempDir.path, 'data', 'venera.db')).existsSync(),
      isTrue,
    );
    expect(File(p.join(tempDir.path, 'history.db')).existsSync(), isFalse);
    expect(File(p.join(tempDir.path, 'local.db')).existsSync(), isFalse);
    expect(
      File(p.join(tempDir.path, 'local_favorite.db')).existsSync(),
      isFalse,
    );
  });

  test(
    'runtime component init wires comic detail repository with reader sessions',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'app-boot-detail-repo-',
      );
      addTearDown(() async {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      });

      final store = UnifiedComicsStore(
        p.join(tempDir.path, 'data', 'venera.db'),
      );
      addTearDown(store.close);

      await App.initRuntimeComponents(
        initAppData: () async {},
        canonicalStore: store,
        initCanonicalStore: store.init,
        seedSourcePlatforms: store.seedDefaultSourcePlatforms,
      );

      await store.upsertComic(
        const ComicRecord(
          id: 'comic-detail-runtime',
          title: 'Runtime Detail',
          normalizedTitle: 'runtime detail',
        ),
      );
      final detail = await App.repositories.comicDetail.getComicDetail(
        'comic-detail-runtime',
      );
      expect(detail, isNotNull);
      expect(detail!.readerTabs, isEmpty);
    },
  );

  test('App.init uses runtime root override from host channel', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'app-runtime-root-override-',
    );
    addTearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });
    await mockPathProvider(tempDir);
    final overrideRoot = p.join(tempDir.path, 'dev-runtime-root');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(appChannel, (call) async {
          if (call.method == 'getRuntimeRootOverride') {
            return overrideRoot;
          }
          return null;
        });

    await App.init();

    expect(App.runtimeRootOverrideActive, isTrue);
    expect(App.runtimeRootOverridePath, overrideRoot);
    expect(App.dataPath, overrideRoot);
    expect(App.cachePath, p.join(overrideRoot, 'cache'));
  });
}
