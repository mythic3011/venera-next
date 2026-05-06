import 'package:venera/foundation/db/unified_comics_store.dart';

/// legacy-compatible: temporarily exposes persistence-shaped records.
abstract class ReaderSessionStorePort {
  Future<ReaderSessionRecord?> loadReaderSessionByComic(String comicId);
  Future<List<ReaderTabRecord>> loadReaderTabsForSession(String sessionId);
  Future<void> upsertReaderSession(ReaderSessionRecord record);
  Future<void> upsertReaderTab(ReaderTabRecord record);
  Future<void> setReaderSessionActiveTab({
    required String sessionId,
    required String activeTabId,
  });
  Future<void> deleteReaderSession(String sessionId);
}
