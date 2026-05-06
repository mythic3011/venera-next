import 'package:venera/foundation/diagnostics/diagnostics.dart';

import 'models.dart';

class ReaderResumeSession {
  const ReaderResumeSession({
    required this.canonicalComicId,
    required this.sourceRef,
    required this.chapterRefId,
    required this.page,
    this.pageOrderId,
  });

  final String canonicalComicId;
  final SourceRef sourceRef;
  final String chapterRefId;
  final int page;
  final String? pageOrderId;

  void validate() {
    if (sourceRef.type == SourceRefType.local) {
      if (canonicalComicId.trim().isEmpty) {
        _recordLocalResumeRejected('CANONICAL_ID_INVALID');
        throw ReaderRuntimeException(
          'CANONICAL_ID_INVALID',
          'Local resume session comic identity is missing',
        );
      }
      if (sourceRef.sourceKey.trim().isEmpty ||
          sourceRef.upstreamComicRefId.trim().isEmpty) {
        _recordLocalResumeRejected('SOURCE_REF_INVALID');
        throw ReaderRuntimeException(
          'SOURCE_REF_INVALID',
          'Local resume session SourceRef is malformed',
        );
      }
      if (chapterRefId.isEmpty || page < 0) {
        _recordLocalResumeRejected('SESSION_INVALID');
        throw ReaderRuntimeException(
          'SESSION_INVALID',
          'Resume session is malformed',
        );
      }
      AppDiagnostics.info(
        'reader.local',
        'reader.local.resume.accepted',
        data: _diagnosticData(),
      );
      if (pageOrderId == null || pageOrderId!.trim().isEmpty) {
        AppDiagnostics.info(
          'reader.local',
          'reader.local.resume.pageOrderFallback',
          data: {
            ..._diagnosticData(),
            'fallback': 'currentPageIndex:fileOrder',
          },
        );
      }
      return;
    }

    if (sourceRef.type != SourceRefType.remote) {
      throw ReaderRuntimeException(
        'SOURCE_REF_REQUIRED',
        'Resume session requires remote SourceRef for remote reader flow',
      );
    }
    if (!canonicalComicId.contains(':')) {
      throw ReaderRuntimeException(
        'CANONICAL_ID_INVALID',
        'Resume session canonicalComicId must be namespaced',
      );
    }
    if (chapterRefId.isEmpty || page < 0) {
      throw ReaderRuntimeException(
        'SESSION_INVALID',
        'Resume session is malformed',
      );
    }
  }

  void _recordLocalResumeRejected(String reason) {
    AppDiagnostics.warn(
      'reader.local',
      'reader.local.resume.rejected',
      data: {..._diagnosticData(), 'reason': reason},
    );
  }

  Map<String, Object?> _diagnosticData() {
    return {
      'loadMode': 'local',
      'sourceKey': sourceRef.sourceKey,
      'comicId': canonicalComicId,
      'chapterId': chapterRefId,
      'page': page,
      'pageOrderId': pageOrderId,
    };
  }
}

abstract interface class ReaderSessionStore {
  Future<void> save(ReaderResumeSession session);

  Future<ReaderResumeSession?> load({required String canonicalComicId});
}

class InMemoryReaderSessionStore implements ReaderSessionStore {
  final Map<String, ReaderResumeSession> _sessions =
      <String, ReaderResumeSession>{};

  @override
  Future<void> save(ReaderResumeSession session) async {
    session.validate();
    _sessions[session.canonicalComicId] = session;
  }

  @override
  Future<ReaderResumeSession?> load({required String canonicalComicId}) async {
    return _sessions[canonicalComicId];
  }
}
