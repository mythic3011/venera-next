import 'package:venera/foundation/db/unified_comics_store.dart';

/// legacy-compatible: temporarily exposes persistence-shaped records.
abstract class LocalLibraryBrowseStorePort {
  Future<List<LocalLibraryBrowseRecord>> loadLocalLibraryBrowseRecords();
  Future<LocalLibraryItemRecord?> loadPrimaryLocalLibraryItem(String comicId);
  Future<List<String>> loadChapterIdsForComic(String comicId);
}
