import 'dart:convert';

import 'package:venera/foundation/db/store_records.dart';
import 'package:venera/foundation/ports/remote_match_store_port.dart';

String buildPromotedComicSourceLinkId({
  required String comicId,
  required String sourcePlatformId,
  required String sourceComicId,
}) {
  return 'source_link:${Uri.encodeComponent(comicId)}:$sourcePlatformId:${Uri.encodeComponent(sourceComicId)}';
}

class RemoteMatchRepository {
  const RemoteMatchRepository({required this.store});

  final RemoteMatchStorePort store;

  Future<List<RemoteMatchCandidateRecord>> listCandidates(String comicId) {
    return store.loadRemoteMatchCandidates(comicId);
  }

  Future<void> upsertCandidate(RemoteMatchCandidateRecord candidate) {
    return store.upsertRemoteMatchCandidate(candidate);
  }

  Future<void> rejectCandidate({
    required String comicId,
    required String candidateId,
  }) async {
    final candidate = await _loadCandidate(
      comicId: comicId,
      candidateId: candidateId,
    );
    if (candidate == null) {
      throw StateError(
        'Remote match candidate $candidateId not found for comic $comicId.',
      );
    }
    await store.upsertRemoteMatchCandidate(
      RemoteMatchCandidateRecord(
        id: candidate.id,
        comicId: candidate.comicId,
        sourcePlatformId: candidate.sourcePlatformId,
        sourceComicId: candidate.sourceComicId,
        sourceUrl: candidate.sourceUrl,
        sourceTitle: candidate.sourceTitle,
        confidence: candidate.confidence,
        metadataJson: candidate.metadataJson,
        status: 'rejected',
        createdAt: candidate.createdAt,
        updatedAt: candidate.updatedAt,
      ),
    );
  }

  Future<void> acceptCandidate({
    required String comicId,
    required String candidateId,
    bool makePrimary = false,
  }) async {
    final candidate = await _loadCandidate(
      comicId: comicId,
      candidateId: candidateId,
    );
    if (candidate == null) {
      throw StateError(
        'Remote match candidate $candidateId not found for comic $comicId.',
      );
    }
    final primaryLink = await store.loadPrimaryComicSourceLink(comicId);
    final metadata = _CandidateMetadata.fromJson(candidate.metadataJson);
    final linkId = buildPromotedComicSourceLinkId(
      comicId: comicId,
      sourcePlatformId: candidate.sourcePlatformId,
      sourceComicId: candidate.sourceComicId,
    );

    await store.transaction(() async {
      await store.upsertRemoteMatchCandidate(
        RemoteMatchCandidateRecord(
          id: candidate.id,
          comicId: candidate.comicId,
          sourcePlatformId: candidate.sourcePlatformId,
          sourceComicId: candidate.sourceComicId,
          sourceUrl: candidate.sourceUrl,
          sourceTitle: candidate.sourceTitle,
          confidence: candidate.confidence,
          metadataJson: candidate.metadataJson,
          status: 'accepted',
          createdAt: candidate.createdAt,
          updatedAt: candidate.updatedAt,
        ),
      );
      await store.upsertComicSourceLink(
        ComicSourceLinkRecord(
          id: linkId,
          comicId: comicId,
          sourcePlatformId: candidate.sourcePlatformId,
          sourceComicId: candidate.sourceComicId,
          linkStatus: 'active',
          isPrimary: makePrimary || primaryLink == null,
          sourceUrl: candidate.sourceUrl,
          sourceTitle: candidate.sourceTitle,
          downloadedAt: metadata.downloadedAt,
          lastVerifiedAt: metadata.lastVerifiedAt,
          metadataJson: candidate.metadataJson,
        ),
      );
    });
  }

  Future<RemoteMatchCandidateRecord?> _loadCandidate({
    required String comicId,
    required String candidateId,
  }) async {
    final candidates = await store.loadRemoteMatchCandidates(comicId);
    for (final candidate in candidates) {
      if (candidate.id == candidateId) {
        return candidate;
      }
    }
    return null;
  }
}

class _CandidateMetadata {
  const _CandidateMetadata({this.downloadedAt, this.lastVerifiedAt});

  final String? downloadedAt;
  final String? lastVerifiedAt;

  factory _CandidateMetadata.fromJson(String rawJson) {
    try {
      final decoded = jsonDecode(rawJson);
      if (decoded is! Map<String, dynamic>) {
        return const _CandidateMetadata();
      }
      return _CandidateMetadata(
        downloadedAt: decoded['downloaded_at']?.toString(),
        lastVerifiedAt: decoded['last_verified_at']?.toString(),
      );
    } catch (_) {
      return const _CandidateMetadata();
    }
  }
}
