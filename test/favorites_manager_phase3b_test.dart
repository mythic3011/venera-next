import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera/foundation/app.dart';
import 'package:venera/foundation/appdata.dart';
import 'package:venera/foundation/comic_type.dart';
import 'package:venera/foundation/favorites.dart';

FavoriteItem buildComic(String id) {
  return FavoriteItem(
    id: id,
    name: 'name-$id',
    coverPath: '/$id.jpg',
    author: 'author-$id',
    type: ComicType.local,
    tags: const ['t1'],
  );
}

Future<void> waitUntil(bool Function() check) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (DateTime.now().isBefore(deadline)) {
    if (check()) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  throw StateError('condition not met before timeout');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory baseTempDir;
  late Directory tempDir;
  late LocalFavoritesManager manager;

  setUpAll(() async {
    baseTempDir = Directory.systemTemp.createTempSync('venera-fav-manager-test-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'getApplicationSupportDirectory' ||
              call.method == 'getApplicationDocumentsDirectory' ||
              call.method == 'getApplicationCacheDirectory') {
            return tempDir.path;
          }
          return tempDir.path;
        });
  });

  setUp(() async {
    tempDir = Directory(
      '${baseTempDir.path}/case_${DateTime.now().microsecondsSinceEpoch}',
    )..createSync(recursive: true);
    App.dataPath = tempDir.path;
    App.cachePath = tempDir.path;

    await appdata.init();
    appdata.settings['newFavoriteAddTo'] = 'end';
    appdata.settings['followUpdatesFolder'] = null;

    LocalFavoritesManager.cache = null;
    manager = LocalFavoritesManager();
    await manager.init();
  });

  tearDown(() async {
    manager.close();
    LocalFavoritesManager.cache = null;
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  tearDownAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    if (baseTempDir.existsSync()) {
      baseTempDir.deleteSync(recursive: true);
    }
  });

  test('phase3b manager writes keep counts/hash and folder outcomes', () async {
    final src = manager.createFolder('src_phase3b');
    final dst = manager.createFolder('dst_phase3b');

    final c1 = buildComic('c1');
    final c2 = buildComic('c2');
    final c3 = buildComic('c3');

    expect(manager.addComic(src, c1), isTrue);
    expect(manager.addComic(src, c2), isTrue);
    expect(manager.addComic(src, c1), isFalse);

    expect(manager.folderComics(src), 2);
    expect(manager.isExist(c1.id, c1.type), isTrue);
    expect(manager.isExist(c2.id, c2.type), isTrue);

    manager.deleteComicWithId(src, c1.id, c1.type);
    expect(manager.folderComics(src), 1);
    expect(manager.isExist(c1.id, c1.type), isFalse);

    manager.batchDeleteComics(src, [c2]);
    expect(manager.folderComics(src), 0);
    expect(manager.isExist(c2.id, c2.type), isFalse);

    expect(manager.addComic(src, c1), isTrue);
    expect(manager.addComic(src, c2), isTrue);
    expect(manager.addComic(src, c3), isTrue);

    manager.moveFavorite(src, dst, c1.id, c1.type);
    expect(
      manager.getFolderComics(dst).any((e) => e.id == c1.id && e.type == c1.type),
      isTrue,
    );
    expect(
      manager.getFolderComics(src).any((e) => e.id == c1.id && e.type == c1.type),
      isFalse,
    );

    manager.batchCopyFavorites(src, dst, [c2, c3]);
    expect(
      manager.getFolderComics(dst).where((e) => e.id == c2.id).isNotEmpty,
      isTrue,
    );
    expect(
      manager.getFolderComics(dst).where((e) => e.id == c3.id).isNotEmpty,
      isTrue,
    );

    manager.batchMoveFavorites(src, dst, [c2, c3]);
    expect(manager.getFolderComics(src).isEmpty, isTrue);
    expect(manager.folderComics(src), 0);
    expect(manager.folderComics(dst) >= 3, isTrue);

    await waitUntil(() => manager.isExist(c1.id, c1.type));
    await waitUntil(() => manager.isExist(c2.id, c2.type));
    await waitUntil(() => manager.isExist(c3.id, c3.type));
  });

  test('addComic respects newFavoriteAddTo start/end display order direction', () async {
    final folder = manager.createFolder('order_phase3b');
    final c1 = buildComic('o1');
    final c2 = buildComic('o2');
    final c3 = buildComic('o3');
    final c4 = buildComic('o4');

    appdata.settings['newFavoriteAddTo'] = 'end';
    expect(manager.addComic(folder, c1), isTrue);
    expect(manager.addComic(folder, c2), isTrue);
    expect(
      manager.getFolderComics(folder).map((e) => e.id).toList(),
      ['o1', 'o2'],
    );

    appdata.settings['newFavoriteAddTo'] = 'start';
    expect(manager.addComic(folder, c3), isTrue);
    expect(
      manager.getFolderComics(folder).map((e) => e.id).toList(),
      ['o3', 'o1', 'o2'],
    );

    appdata.settings['newFavoriteAddTo'] = 'end';
    expect(manager.addComic(folder, c4), isTrue);
    expect(
      manager.getFolderComics(folder).map((e) => e.id).toList(),
      ['o3', 'o1', 'o2', 'o4'],
    );
  });
}
