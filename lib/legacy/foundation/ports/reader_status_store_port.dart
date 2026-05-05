import 'package:venera/foundation/db/unified_comics_store.dart';

/// legacy-compatible: temporarily exposes persistence-shaped records.
abstract class ReaderStatusStorePort {
  Future<Map<String, ReaderStatusRecord>> loadReaderStatusesForComics(
    List<String> comicIds,
  );
}
