import 'package:venera/foundation/db/unified_comics_store.dart';

/// legacy-compatible: temporarily exposes persistence-shaped records.
abstract class ReaderActivityStorePort {
  Future<List<ReaderActivityRecord>> loadReaderActivity({int? limit});
  Future<int> countReaderActivity();
  Future<void> deleteReaderActivity(String comicId);
  Future<void> clearReaderActivity();
}
