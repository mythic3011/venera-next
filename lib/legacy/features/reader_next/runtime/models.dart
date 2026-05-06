class ReaderRuntimeException implements Exception {
  ReaderRuntimeException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => '$code: $message';
}

class ReaderNextBoundaryException extends ReaderRuntimeException {
  ReaderNextBoundaryException(super.code, super.message);
}

enum SourceRefType { remote, local }

class SourceRef {
  const SourceRef._({
    required this.type,
    required this.sourceKey,
    required this.upstreamComicRefId,
    required this.chapterRefId,
  });

  factory SourceRef.remote({
    required String sourceKey,
    required String upstreamComicRefId,
    String? chapterRefId,
  }) {
    if (sourceKey.isEmpty) {
      throw ReaderNextBoundaryException(
        'SOURCE_REF_INVALID',
        'sourceKey is required for remote SourceRef',
      );
    }
    if (upstreamComicRefId.isEmpty) {
      throw ReaderNextBoundaryException(
        'SOURCE_REF_INVALID',
        'upstreamComicRefId is required for remote SourceRef',
      );
    }
    if (_looksCanonical(upstreamComicRefId)) {
      throw ReaderNextBoundaryException(
        'SOURCE_REF_INVALID',
        'upstreamComicRefId must not be canonical',
      );
    }
    return SourceRef._(
      type: SourceRefType.remote,
      sourceKey: sourceKey,
      upstreamComicRefId: upstreamComicRefId,
      chapterRefId: chapterRefId,
    );
  }

  factory SourceRef.local({
    required String sourceKey,
    required String comicRefId,
    String? chapterRefId,
  }) {
    if (sourceKey.isEmpty || comicRefId.isEmpty) {
      throw ReaderRuntimeException('SOURCE_REF_INVALID', 'Local SourceRef is malformed');
    }
    return SourceRef._(
      type: SourceRefType.local,
      sourceKey: sourceKey,
      upstreamComicRefId: comicRefId,
      chapterRefId: chapterRefId,
    );
  }

  final SourceRefType type;
  final String sourceKey;
  final String upstreamComicRefId;
  final String? chapterRefId;

  bool get isRemote => type == SourceRefType.remote;

  static bool _looksCanonical(String id) => id.contains(':');
}

class ComicIdentity {
  const ComicIdentity({
    required this.canonicalComicId,
    required this.sourceRef,
  });

  final String canonicalComicId;
  final SourceRef sourceRef;

  void assertRemoteOperationSafe() {
    if (!sourceRef.isRemote) {
      throw ReaderRuntimeException(
        'SOURCE_REF_REQUIRED',
        'Remote reader operation requires remote SourceRef',
      );
    }
    if (canonicalComicId.isEmpty || !canonicalComicId.contains(':')) {
      throw ReaderRuntimeException(
        'CANONICAL_ID_INVALID',
        'canonicalComicId must be namespaced and non-empty',
      );
    }
    if (sourceRef.upstreamComicRefId.contains(':')) {
      throw ReaderRuntimeException(
        'UPSTREAM_ID_INVALID',
        'upstream ID must never be canonical',
      );
    }
  }
}

class CanonicalComicId {
  const CanonicalComicId._(this.value);

  factory CanonicalComicId.remote({
    required String sourceKey,
    required String upstreamComicRefId,
  }) {
    if (sourceKey.isEmpty || upstreamComicRefId.isEmpty) {
      throw ReaderNextBoundaryException(
        'CANONICAL_ID_INVALID',
        'remote canonical comic id is malformed',
      );
    }
    if (_looksCanonical(upstreamComicRefId)) {
      throw ReaderNextBoundaryException(
        'CANONICAL_ID_INVALID',
        'upstreamComicRefId must not be canonical when building canonical id',
      );
    }
    return CanonicalComicId._('remote:$sourceKey:$upstreamComicRefId');
  }

  final String value;

  factory CanonicalComicId.local({
    required String localComicId,
  }) {
    final normalized = localComicId.trim();
    if (normalized.isEmpty) {
      throw ReaderNextBoundaryException(
        'CANONICAL_ID_INVALID',
        'local canonical comic id is malformed',
      );
    }
    return CanonicalComicId._('local:$normalized');
  }

  static bool _looksCanonical(String id) => id.contains(':');
}

class ReaderNextOpenRequest {
  ReaderNextOpenRequest._({
    required this.canonicalComicId,
    required this.sourceRef,
    required this.initialPage,
  });

  factory ReaderNextOpenRequest.remote({
    required CanonicalComicId canonicalComicId,
    required SourceRef sourceRef,
    required int initialPage,
  }) {
    if (!sourceRef.isRemote) {
      throw ReaderNextBoundaryException(
        'SOURCE_REF_REQUIRED',
        'Remote ReaderNext open request requires valid SourceRef',
      );
    }
    if (initialPage < 1) {
      throw ReaderNextBoundaryException(
        'INITIAL_PAGE_INVALID',
        'initialPage must be >= 1 for ReaderNext remote open request',
      );
    }
    return ReaderNextOpenRequest._(
      canonicalComicId: canonicalComicId,
      sourceRef: sourceRef,
      initialPage: initialPage,
    );
  }

  factory ReaderNextOpenRequest.local({
    required CanonicalComicId canonicalComicId,
    required SourceRef sourceRef,
    required int initialPage,
  }) {
    if (sourceRef.type != SourceRefType.local) {
      throw ReaderNextBoundaryException(
        'SOURCE_REF_REQUIRED',
        'Local ReaderNext open request requires local SourceRef',
      );
    }
    if (initialPage < 1) {
      throw ReaderNextBoundaryException(
        'INITIAL_PAGE_INVALID',
        'initialPage must be >= 1 for ReaderNext local open request',
      );
    }
    return ReaderNextOpenRequest._(
      canonicalComicId: canonicalComicId,
      sourceRef: sourceRef,
      initialPage: initialPage,
    );
  }

  final CanonicalComicId canonicalComicId;
  final SourceRef sourceRef;
  final int initialPage;
}

class SearchQuery {
  const SearchQuery({required this.keyword, required this.page});

  final String keyword;
  final int page;
}

class SearchResultItem {
  const SearchResultItem({
    required this.upstreamComicRefId,
    required this.title,
    required this.cover,
    required this.tags,
  });

  final String upstreamComicRefId;
  final String title;
  final String cover;
  final List<String> tags;
}

class ComicDetailResult {
  const ComicDetailResult({
    required this.title,
    required this.description,
    required this.chapters,
  });

  final String title;
  final String description;
  final List<ChapterRef> chapters;
}

class ChapterRef {
  const ChapterRef({required this.chapterRefId, required this.title});

  final String chapterRefId;
  final String title;
}

class ReaderImageRef {
  const ReaderImageRef({
    required this.imageKey,
    required this.imageUrl,
  });

  final String imageKey;
  final String imageUrl;
}
