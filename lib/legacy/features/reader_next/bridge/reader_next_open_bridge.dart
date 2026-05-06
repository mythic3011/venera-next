import 'package:venera/features/reader_next/runtime/models.dart';

/// Narrow one-way adapter input from existing app entrypoints.
class ReaderNextBridgeInput {
  const ReaderNextBridgeInput({
    required this.sourceKey,
    required this.upstreamComicRefId,
    required this.chapterRefId,
    this.initialPage = 1,
  });

  final String? sourceKey;
  final String? upstreamComicRefId;
  final String? chapterRefId;
  final int initialPage;
}

enum ReaderNextBridgeDecision { readerNext, legacyReader, blocked }

enum ReaderNextBridgeDiagnosticCode {
  missingSourceKey,
  missingUpstreamComicRefId,
  emptyChapterRefId,
  canonicalIdInUpstreamField,
}

class ReaderNextBridgeDiagnostic {
  const ReaderNextBridgeDiagnostic({
    required this.code,
    required this.message,
  });

  final ReaderNextBridgeDiagnosticCode code;
  final String message;
}

class ReaderNextBridgeResult {
  const ReaderNextBridgeResult._({
    required this.decision,
    this.request,
    this.diagnostic,
  });

  factory ReaderNextBridgeResult.readerNext(ReaderNextOpenRequest request) {
    return ReaderNextBridgeResult._(
      decision: ReaderNextBridgeDecision.readerNext,
      request: request,
    );
  }

  factory ReaderNextBridgeResult.blocked(ReaderNextBridgeDiagnostic diagnostic) {
    return ReaderNextBridgeResult._(
      decision: ReaderNextBridgeDecision.blocked,
      diagnostic: diagnostic,
    );
  }

  final ReaderNextBridgeDecision decision;
  final ReaderNextOpenRequest? request;
  final ReaderNextBridgeDiagnostic? diagnostic;

  bool get isBlocked => decision == ReaderNextBridgeDecision.blocked;
}

class ReaderNextOpenBridge {
  const ReaderNextOpenBridge();

  static const String _localSourceKey = 'local';

  static ReaderNextBridgeResult fromLegacyRemote({
    required String? sourceKey,
    required String? comicId,
    required String? chapterId,
    int initialPage = 1,
  }) {
    if (sourceKey == null || sourceKey.isEmpty) {
      return ReaderNextBridgeResult.blocked(
        const ReaderNextBridgeDiagnostic(
          code: ReaderNextBridgeDiagnosticCode.missingSourceKey,
          message: 'sourceKey is required for ReaderNext bridge open request',
        ),
      );
    }
    if (comicId == null || comicId.isEmpty) {
      return ReaderNextBridgeResult.blocked(
        const ReaderNextBridgeDiagnostic(
          code: ReaderNextBridgeDiagnosticCode.missingUpstreamComicRefId,
          message:
              'upstreamComicRefId is required for ReaderNext bridge open request',
        ),
      );
    }
    if (chapterId == null || chapterId.isEmpty) {
      return ReaderNextBridgeResult.blocked(
        const ReaderNextBridgeDiagnostic(
          code: ReaderNextBridgeDiagnosticCode.emptyChapterRefId,
          message: 'chapterRefId is required for ReaderNext bridge open request',
        ),
      );
    }
    if (_looksCanonical(comicId)) {
      return ReaderNextBridgeResult.blocked(
        const ReaderNextBridgeDiagnostic(
          code: ReaderNextBridgeDiagnosticCode.canonicalIdInUpstreamField,
          message:
              'bridge must not accept canonical IDs in upstreamComicRefId field',
        ),
      );
    }

    final sourceRef = SourceRef.remote(
      sourceKey: sourceKey,
      upstreamComicRefId: comicId,
      chapterRefId: chapterId,
    );
    final canonicalComicId = CanonicalComicId.remote(
      sourceKey: sourceKey,
      upstreamComicRefId: comicId,
    );
    return ReaderNextBridgeResult.readerNext(
      ReaderNextOpenRequest.remote(
        canonicalComicId: canonicalComicId,
        sourceRef: sourceRef,
        initialPage: initialPage,
      ),
    );
  }

  static ReaderNextBridgeResult fromLegacy({
    required String? sourceKey,
    required String? comicId,
    required String? chapterId,
    int initialPage = 1,
  }) {
    final normalizedSourceKey = sourceKey?.trim() ?? '';
    if (normalizedSourceKey == _localSourceKey) {
      if (comicId == null || comicId.trim().isEmpty) {
        return ReaderNextBridgeResult.blocked(
          const ReaderNextBridgeDiagnostic(
            code: ReaderNextBridgeDiagnosticCode.missingUpstreamComicRefId,
            message:
                'local comic identity is required for ReaderNext bridge open request',
          ),
        );
      }
      if (chapterId == null || chapterId.trim().isEmpty) {
        return ReaderNextBridgeResult.blocked(
          const ReaderNextBridgeDiagnostic(
            code: ReaderNextBridgeDiagnosticCode.emptyChapterRefId,
            message: 'chapterRefId is required for ReaderNext bridge open request',
          ),
        );
      }
      final localComicId = comicId.trim();
      final localChapterRefId = chapterId.trim();
      final sourceRef = SourceRef.local(
        sourceKey: _localSourceKey,
        comicRefId: localComicId,
        chapterRefId: localChapterRefId,
      );
      return ReaderNextBridgeResult.readerNext(
        ReaderNextOpenRequest.local(
          canonicalComicId: CanonicalComicId.local(localComicId: localComicId),
          sourceRef: sourceRef,
          initialPage: initialPage,
        ),
      );
    }
    return fromLegacyRemote(
      sourceKey: sourceKey,
      comicId: comicId,
      chapterId: chapterId,
      initialPage: initialPage,
    );
  }

  ReaderNextOpenRequest toOpenRequest({required ReaderNextBridgeInput input}) {
    final sourceKey = _requireNonEmpty(fieldName: 'sourceKey', value: input.sourceKey);
    final upstreamComicRefId = _requireNonEmpty(
      fieldName: 'upstreamComicRefId',
      value: input.upstreamComicRefId,
    );
    final chapterRefId = _requireNonEmpty(
      fieldName: 'chapterRefId',
      value: input.chapterRefId,
    );

    if (sourceKey == _localSourceKey) {
      final sourceRef = SourceRef.local(
        sourceKey: sourceKey,
        comicRefId: upstreamComicRefId,
        chapterRefId: chapterRefId,
      );
      return ReaderNextOpenRequest.local(
        canonicalComicId: CanonicalComicId.local(
          localComicId: upstreamComicRefId,
        ),
        sourceRef: sourceRef,
        initialPage: input.initialPage,
      );
    }

    final sourceRef = SourceRef.remote(
      sourceKey: sourceKey,
      upstreamComicRefId: upstreamComicRefId,
      chapterRefId: chapterRefId,
    );
    final canonicalComicId = CanonicalComicId.remote(
      sourceKey: sourceKey,
      upstreamComicRefId: upstreamComicRefId,
    );

    return ReaderNextOpenRequest.remote(
      canonicalComicId: canonicalComicId,
      sourceRef: sourceRef,
      initialPage: input.initialPage,
    );
  }

  String _requireNonEmpty({
    required String fieldName,
    required String? value,
  }) {
    if (value == null || value.isEmpty) {
      throw ReaderNextBoundaryException(
        'SOURCE_REF_INVALID',
        '$fieldName is required for ReaderNext bridge open request',
      );
    }
    return value;
  }

  static bool _looksCanonical(String id) => id.contains(':');
}
