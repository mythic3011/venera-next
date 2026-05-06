import 'package:venera/foundation/db/unified_comics_store.dart';
import 'package:venera/foundation/ports/remote_match_store_port.dart';

class UnifiedRemoteMatchStoreAdapter implements RemoteMatchStorePort {
  const UnifiedRemoteMatchStoreAdapter(this.store);

  final UnifiedComicsStore store;

  @override
  Future<ComicSourceLinkRecord?> loadPrimaryComicSourceLink(String comicId) {
    return store.loadPrimaryComicSourceLink(comicId);
  }

  @override
  Future<List<RemoteMatchCandidateRecord>> loadRemoteMatchCandidates(
    String comicId,
  ) {
    return store.loadRemoteMatchCandidates(comicId);
  }

  @override
  Future<T> transaction<T>(Future<T> Function() action) {
    return store.transaction(action);
  }

  @override
  Future<void> upsertComicSourceLink(ComicSourceLinkRecord record) {
    return store.upsertComicSourceLink(record);
  }

  @override
  Future<void> upsertRemoteMatchCandidate(
    RemoteMatchCandidateRecord candidate,
  ) {
    return store.upsertRemoteMatchCandidate(candidate);
  }
}
