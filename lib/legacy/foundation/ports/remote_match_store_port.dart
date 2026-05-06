import 'package:venera/foundation/db/unified_comics_store.dart';

/// legacy-compatible: temporarily exposes persistence-shaped records.
abstract class RemoteMatchStorePort {
  Future<List<RemoteMatchCandidateRecord>> loadRemoteMatchCandidates(
    String comicId,
  );
  Future<void> upsertRemoteMatchCandidate(RemoteMatchCandidateRecord candidate);
  Future<ComicSourceLinkRecord?> loadPrimaryComicSourceLink(String comicId);
  Future<void> upsertComicSourceLink(ComicSourceLinkRecord record);
  Future<T> transaction<T>(Future<T> Function() action);
}
