import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera/foundation/app.dart';
import 'package:venera/foundation/appdata.dart';
import 'package:venera/foundation/comic_type.dart';
import 'package:venera/foundation/favorite_runtime_authority.dart';
import 'package:venera/foundation/favorites.dart';
import 'package:venera/foundation/history.dart';

FavoriteItem _favoriteItem(String id, ComicType type) {
  return FavoriteItem(
    id: id,
    name: 'comic-$id',
    coverPath: '/$id.png',
    author: 'author-$id',
    type: type,
    tags: const ['tag:a'],
  );
}

History _historyItem(String id, ComicType type) {
  return History.fromMap({
    'type': type.value,
    'time': DateTime.now().millisecondsSinceEpoch,
    'title': 'history-$id',
    'subtitle': 'sub-$id',
    'cover': '/$id.png',
    'ep': 1,
    'page': 1,
    'id': id,
    'readEpisode': <String>[],
    'max_page': null,
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory baseTempDir;
  late Directory tempDir;
  late LocalFavoritesManager favoritesManager;
  late HistoryManager historyManager;

  setUpAll(() async {
    baseTempDir = Directory.systemTemp.createTempSync(
      'venera-favorite-authority-regression-',
    );
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
    favoritesManager = LocalFavoritesManager();
    await favoritesManager.init();

    HistoryManager.cache = null;
    historyManager = HistoryManager();
    await historyManager.init();
  });

  tearDown(() async {
    await historyManager.close();
    HistoryManager.cache = null;
    await favoritesManager.close();
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

  test('favorite panel authority path keeps folder/membership/add/remove parity', () {
    const folder = 'panel-folder';
    const comicId = 'panel-comic';
    final item = _favoriteItem(comicId, ComicType.local);

    favoritesManager.createFolder(folder);
    FavoriteRuntimeAuthority.addComic(folder, item, '2026-05-04');

    expect(FavoriteRuntimeAuthority.folderNames(), contains(folder));
    expect(
      FavoriteRuntimeAuthority.membershipForComic(comicId, ComicType.local),
      contains(folder),
    );
    expect(FavoriteRuntimeAuthority.exists(comicId, ComicType.local), isTrue);

    FavoriteRuntimeAuthority.deleteComic(folder, comicId, ComicType.local);

    expect(FavoriteRuntimeAuthority.exists(comicId, ComicType.local), isFalse);
    expect(
      FavoriteRuntimeAuthority.membershipForComic(comicId, ComicType.local),
      isEmpty,
    );
  });

  test('follow-updates authority path keeps update count and mark-as-read parity', () {
    const folder = 'follow-folder';
    const comicId = 'follow-comic';
    final item = _favoriteItem(comicId, ComicType.local);

    favoritesManager.createFolder(folder);
    FavoriteRuntimeAuthority.addComic(folder, item, '2026-05-01');
    FavoriteRuntimeAuthority.prepareTableForFollowUpdates(folder);

    appdata.settings['followUpdatesFolder'] = folder;
    FavoriteRuntimeAuthority.updateUpdateTime(
      folder,
      comicId,
      ComicType.local,
      '2026-05-02',
    );

    expect(FavoriteRuntimeAuthority.countUpdates(folder), 1);
    final comics = FavoriteRuntimeAuthority.comicsWithUpdatesInfo(folder);
    expect(comics, hasLength(1));
    expect(comics.single.hasNewUpdate, isTrue);

    FavoriteRuntimeAuthority.markAsRead(comicId, ComicType.local);
    FavoriteRuntimeAuthority.updateCheckTime(folder, comicId, ComicType.local);

    expect(FavoriteRuntimeAuthority.countUpdates(folder), 0);
  });

  test('history clearUnfavoritedHistory keeps favorite-existence semantics via authority', () async {
    const folder = 'history-folder';
    const keepId = 'history-keep';
    const dropId = 'history-drop';

    favoritesManager.createFolder(folder);
    FavoriteRuntimeAuthority.addComic(
      folder,
      _favoriteItem(keepId, ComicType.local),
      '2026-05-04',
    );

    await historyManager.addHistory(_historyItem(keepId, ComicType.local));
    await historyManager.addHistory(_historyItem(dropId, ComicType.local));

    historyManager.clearUnfavoritedHistory();

    expect(historyManager.find(keepId, ComicType.local), isNotNull);
    expect(historyManager.find(dropId, ComicType.local), isNull);
  });
}
