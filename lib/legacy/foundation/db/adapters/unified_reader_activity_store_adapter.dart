import 'package:venera/foundation/db/unified_comics_store.dart';
import 'package:venera/foundation/ports/reader_activity_store_port.dart';

class UnifiedReaderActivityStoreAdapter implements ReaderActivityStorePort {
  const UnifiedReaderActivityStoreAdapter(this.store);

  final UnifiedComicsStore store;

  @override
  Future<void> clearReaderActivity() {
    return store.clearReaderActivity();
  }

  @override
  Future<int> countReaderActivity() {
    return store.countReaderActivity();
  }

  @override
  Future<void> deleteReaderActivity(String comicId) {
    return store.deleteReaderActivity(comicId);
  }

  @override
  Future<List<ReaderActivityRecord>> loadReaderActivity({int? limit}) {
    return store.loadReaderActivity(limit: limit);
  }
}
