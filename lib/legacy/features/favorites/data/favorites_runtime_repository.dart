import 'package:venera/foundation/comic_type.dart';
import 'package:venera/foundation/favorites.dart';

class FavoritesRuntimeRepository {
  const FavoritesRuntimeRepository();

  LocalFavoritesManager get _manager => LocalFavoritesManager();

  Future<void> init() => _manager.init();

  void addListener(void Function() listener) {
    _manager.addListener(listener);
  }

  void removeListener(void Function() listener) {
    _manager.removeListener(listener);
  }

  List<String> get folderNames => _manager.folderNames;

  int get totalComics => _manager.totalComics;

  int folderComics(String folder) => _manager.folderComics(folder);

  bool existsFolder(String name) => _manager.existsFolder(name);

  String createFolder(String name, [bool renameWhenInvalidName = false]) {
    return _manager.createFolder(name, renameWhenInvalidName);
  }

  void deleteFolder(String name) => _manager.deleteFolder(name);

  void rename(String before, String after) => _manager.rename(before, after);

  List<FavoriteItem> getFolderComics(String folder) => _manager.getFolderComics(folder);

  Future<List<FavoriteItem>> getFolderComicsAsync(String folder) {
    return _manager.getFolderComicsAsync(folder);
  }

  List<FavoriteItem> getAllComics() => _manager.getAllComics();

  Future<List<FavoriteItem>> getAllComicsAsync() => _manager.getAllComicsAsync();

  void addComic(
    String folder,
    FavoriteItem comic, [
    int? order,
    String? updateTime,
  ]) => _manager.addComic(folder, comic, order, updateTime);

  bool comicExists(String folder, String id, ComicType type) {
    return _manager.comicExists(folder, id, type);
  }

  void deleteComicWithId(String folder, String id, ComicType type) {
    _manager.deleteComicWithId(folder, id, type);
  }

  void batchMoveFavorites(
    String sourceFolder,
    String targetFolder,
    List<FavoriteItem> items,
  ) => _manager.batchMoveFavorites(sourceFolder, targetFolder, items);

  void batchCopyFavorites(
    String sourceFolder,
    String targetFolder,
    List<FavoriteItem> items,
  ) => _manager.batchCopyFavorites(sourceFolder, targetFolder, items);

  void batchDeleteComics(String folder, List<FavoriteItem> comics) {
    _manager.batchDeleteComics(folder, comics);
  }

  void reorder(List<FavoriteItem> newFolder, String folder) {
    _manager.reorder(newFolder, folder);
  }

  String folderToJson(String folder) => _manager.folderToJson(folder);

  void fromJson(String json) => _manager.fromJson(json);

  void updateInfo(String folder, FavoriteItem comic, [bool notify = true]) {
    _manager.updateInfo(folder, comic, notify);
  }

  void updateOrder(List<String> folders) => _manager.updateOrder(folders);

  void linkFolderToNetwork(String folder, String source, String networkFolder) {
    _manager.linkFolderToNetwork(folder, source, networkFolder);
  }

  bool isLinkedToNetworkFolder(
    String folder,
    String source,
    String networkFolder,
  ) {
    return _manager.isLinkedToNetworkFolder(folder, source, networkFolder);
  }

  (String?, String?) findLinked(String folder) => _manager.findLinked(folder);
}
