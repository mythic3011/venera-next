import 'package:venera/foundation/db/unified_comics_store.dart';
import 'package:venera/foundation/ports/local_library_browse_store_port.dart';

class UnifiedLocalLibraryBrowseStoreAdapter
    implements LocalLibraryBrowseStorePort {
  const UnifiedLocalLibraryBrowseStoreAdapter(this.store);

  final UnifiedComicsStore store;

  @override
  Future<List<LocalLibraryBrowseRecord>> loadLocalLibraryBrowseRecords() {
    return store.loadLocalLibraryBrowseRecords();
  }

  @override
  Future<LocalLibraryItemRecord?> loadPrimaryLocalLibraryItem(String comicId) {
    return store.loadPrimaryLocalLibraryItem(comicId);
  }

  @override
  Future<List<String>> loadChapterIdsForComic(String comicId) {
    return store.loadChapterIdsForComic(comicId);
  }

  @override
  Future<void> deleteLocalLibraryItemById(String localLibraryItemId) {
    return store.deleteLocalLibraryItemById(localLibraryItemId);
  }
}
