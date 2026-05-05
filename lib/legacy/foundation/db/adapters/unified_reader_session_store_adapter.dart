import 'package:venera/foundation/db/unified_comics_store.dart';
import 'package:venera/foundation/ports/reader_session_store_port.dart';

class UnifiedReaderSessionStoreAdapter implements ReaderSessionStorePort {
  const UnifiedReaderSessionStoreAdapter(this.store);

  final UnifiedComicsStore store;

  @override
  Future<void> deleteReaderSession(String sessionId) {
    return store.deleteReaderSession(sessionId);
  }

  @override
  Future<ReaderSessionRecord?> loadReaderSessionByComic(String comicId) {
    return store.loadReaderSessionByComic(comicId);
  }

  @override
  Future<List<ReaderTabRecord>> loadReaderTabsForSession(String sessionId) {
    return store.loadReaderTabsForSession(sessionId);
  }

  @override
  Future<void> setReaderSessionActiveTab({
    required String sessionId,
    required String activeTabId,
  }) {
    return store.setReaderSessionActiveTab(
      sessionId: sessionId,
      activeTabId: activeTabId,
    );
  }

  @override
  Future<void> upsertReaderSession(ReaderSessionRecord record) {
    return store.upsertReaderSession(record);
  }

  @override
  Future<void> upsertReaderTab(ReaderTabRecord record) {
    return store.upsertReaderTab(record);
  }
}
