import 'package:venera/foundation/comic_type.dart';
import 'package:venera/foundation/favorites.dart';

class FavoriteRuntimeAuthority {
  const FavoriteRuntimeAuthority._();

  static LocalFavoritesManager get _manager => LocalFavoritesManager();

  static Future<void> ensureInitialized() {
    return _manager.init();
  }

  static bool get isInitialized => _manager.isInitialized;

  static List<String> folderNames() {
    return _manager.folderNames;
  }

  static List<String> membershipForComic(String comicId, ComicType type) {
    return _manager.find(comicId, type);
  }

  static bool exists(String comicId, ComicType type) {
    return _manager.isExist(comicId, type);
  }

  static int count(String folder) {
    return _manager.count(folder);
  }

  static int countUpdates(String folder) {
    return _manager.countUpdates(folder);
  }

  static List<FavoriteItemWithUpdateInfo> comicsWithUpdatesInfo(String folder) {
    return _manager.getComicsWithUpdatesInfo(folder);
  }

  static void markAsRead(String comicId, ComicType type) {
    _manager.markAsRead(comicId, type);
  }

  static void prepareTableForFollowUpdates(String folder) {
    _manager.prepareTableForFollowUpdates(folder);
  }

  static void updateInfo(String folder, FavoriteItem item, bool notify) {
    _manager.updateInfo(folder, item, notify);
  }

  static void updateUpdateTime(
    String folder,
    String comicId,
    ComicType type,
    String updateTime,
  ) {
    _manager.updateUpdateTime(folder, comicId, type, updateTime);
  }

  static void updateCheckTime(String folder, String comicId, ComicType type) {
    _manager.updateCheckTime(folder, comicId, type);
  }

  static void notifyChanges() {
    _manager.notifyChanges();
  }

  static void addComic(
    String folder,
    FavoriteItem item,
    String? updateTime,
  ) {
    _manager.addComic(folder, item, null, updateTime);
  }

  static void deleteComic(String folder, String comicId, ComicType type) {
    _manager.deleteComicWithId(folder, comicId, type);
  }
}
