import 'package:venera/foundation/ports/local_library_browse_store_port.dart';

class LocalLibraryBrowseItem {
  const LocalLibraryBrowseItem({
    required this.comicId,
    required this.title,
    required this.userTags,
    required this.sourceTags,
    this.updatedAt,
  });

  final String comicId;
  final String title;
  final List<String> userTags;
  final List<String> sourceTags;
  final String? updatedAt;
}

class LocalLibraryPrimaryItem {
  const LocalLibraryPrimaryItem({
    required this.id,
    required this.storageType,
    required this.localRootPath,
  });

  final String id;
  final String storageType;
  final String localRootPath;
}

class LocalLibraryRepository {
  const LocalLibraryRepository({required this.store});

  final LocalLibraryBrowseStorePort store;

  Future<List<LocalLibraryBrowseItem>> loadBrowseRecords() async {
    final rows = await store.loadLocalLibraryBrowseRecords();
    return rows
        .map(
          (row) => LocalLibraryBrowseItem(
            comicId: row.comicId,
            title: row.title,
            userTags: row.userTags,
            sourceTags: row.sourceTags,
            updatedAt: row.updatedAt,
          ),
        )
        .toList(growable: false);
  }

  Future<LocalLibraryPrimaryItem?> loadPrimaryLocalLibraryItem(
    String comicId,
  ) async {
    final row = await store.loadPrimaryLocalLibraryItem(comicId);
    if (row == null) {
      return null;
    }
    return LocalLibraryPrimaryItem(
      id: row.id,
      storageType: row.storageType,
      localRootPath: row.localRootPath,
    );
  }

  Future<bool> hasPrimaryLocalLibraryItem(String comicId) async {
    return (await loadPrimaryLocalLibraryItem(comicId)) != null;
  }

  Future<List<String>> loadDownloadedChapterIds(String comicId) {
    return store.loadChapterIdsForComic(comicId);
  }

  Future<void> deleteLocalLibraryItemById(String localLibraryItemId) {
    return store.deleteLocalLibraryItemById(localLibraryItemId);
  }
}
