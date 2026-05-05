import 'package:venera/foundation/db/unified_comics_store.dart';
import 'package:venera/foundation/ports/reader_status_store_port.dart';

class UnifiedReaderStatusStoreAdapter implements ReaderStatusStorePort {
  const UnifiedReaderStatusStoreAdapter(this.store);

  final UnifiedComicsStore store;

  @override
  Future<Map<String, ReaderStatusRecord>> loadReaderStatusesForComics(
    List<String> comicIds,
  ) {
    return store.loadReaderStatusesForComics(comicIds);
  }
}
