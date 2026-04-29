enum ReaderTracePhase {
  sourceResolution,
  pageList,
  thumbnail,
  imageProvider,
  decode,
  cache,
}

class ReaderTraceEvent {
  const ReaderTraceEvent({
    required this.event,
    required this.timestamp,
    required this.phase,
    this.loadMode,
    this.sourceKey,
    this.comicId,
    this.chapterId,
    this.chapterIndex,
    this.page,
    this.imageKey,
    this.thumbnailUrl,
    this.sourceUrl,
    this.errorCode,
    this.errorMessage,
    this.functionName,
    this.callId,
    this.durationMs,
    this.resultSummary,
  });

  final String event;
  final DateTime timestamp;
  final String? loadMode;
  final String? sourceKey;
  final String? comicId;
  final String? chapterId;
  final int? chapterIndex;
  final int? page;
  final String? imageKey;
  final String? thumbnailUrl;
  final String? sourceUrl;
  final String? errorCode;
  final String? errorMessage;
  final String? functionName;
  final String? callId;
  final int? durationMs;
  final String? resultSummary;
  final ReaderTracePhase phase;
}

class ReaderTraceRecorder {
  ReaderTraceRecorder({this.maxEvents = 100});

  final int maxEvents;
  final List<Map<String, dynamic>> _events = [];
  Map<String, dynamic>? _currentReader;

  void clear() {
    _events.clear();
    _currentReader = null;
  }

  void updateReaderState({
    required String lifecycle,
    required String loadMode,
    required String sourceKey,
    required String comicId,
    required int chapterIndex,
    required int page,
    required String mode,
    required bool isLoading,
    required int? imageCount,
    required int? maxPage,
    required int? imagesPerPage,
    String? chapterId,
    ReaderSourceRefSnapshot? sourceRef,
  }) {
    _currentReader = {
      'lifecycle': _capAndRedact(lifecycle, 80),
      'loadMode': _capAndRedact(loadMode, 80),
      'sourceKey': _capAndRedact(sourceKey, 160),
      'comicId': _capAndRedact(comicId, 160),
      'chapterId': _capAndRedact(chapterId, 160),
      'chapterIndex': chapterIndex,
      'page': page,
      'mode': _capAndRedact(mode, 80),
      'isLoading': isLoading,
      'imageCount': imageCount,
      'maxPage': maxPage,
      'imagesPerPage': imagesPerPage,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
      if (sourceRef != null) 'sourceRef': sourceRef.toJson(this),
    };
  }

  void record(ReaderTraceEvent event) {
    if (_events.length >= maxEvents) {
      _events.removeAt(0);
    }
    _events.add(_toJson(event));
  }

  Map<String, dynamic> toDiagnosticsJson() {
    final latestEvent = _events.isEmpty ? null : _events.last;
    final latestError = _events.reversed.firstWhere(
      (event) => event['errorCode'] != null || event['errorMessage'] != null,
      orElse: () => const <String, dynamic>{},
    );
    return {
      'readerTrace': {
        'maxEvents': maxEvents,
        'eventCount': _events.length,
        'currentReader': _currentReader,
        'latestEvent': latestEvent,
        'latestError': latestError.isEmpty ? null : latestError,
        'events': List<Map<String, dynamic>>.from(_events),
      },
    };
  }

  Map<String, dynamic> _toJson(ReaderTraceEvent event) {
    return {
      'event': _capAndRedact(event.event, 160),
      'timestamp': event.timestamp.toUtc().toIso8601String(),
      'loadMode': _capAndRedact(event.loadMode, 160),
      'sourceKey': _capAndRedact(event.sourceKey, 160),
      'comicId': _capAndRedact(event.comicId, 160),
      'chapterId': _capAndRedact(event.chapterId, 160),
      'chapterIndex': event.chapterIndex,
      'page': event.page,
      'imageKey': _stripUrlAndCap(event.imageKey, 120),
      'thumbnailUrl': _stripUrlAndCap(event.thumbnailUrl, 120),
      'sourceUrl': _stripUrlAndCap(event.sourceUrl, 120),
      'errorCode': _capAndRedact(event.errorCode, 160),
      'errorMessage': _capAndRedact(event.errorMessage, 160),
      'functionName': _capAndRedact(event.functionName, 160),
      'callId': _capAndRedact(event.callId, 80),
      'durationMs': event.durationMs,
      'resultSummary': _capAndRedact(event.resultSummary, 200),
      'phase': event.phase.name,
    };
  }

  String? _stripUrlAndCap(String? value, int cap) {
    if (value == null || value.isEmpty) return value;
    var sanitized = value;
    final queryIndex = sanitized.indexOf('?');
    final fragmentIndex = sanitized.indexOf('#');
    var cutIndex = -1;
    if (queryIndex >= 0 && fragmentIndex >= 0) {
      cutIndex = queryIndex < fragmentIndex ? queryIndex : fragmentIndex;
    } else if (queryIndex >= 0) {
      cutIndex = queryIndex;
    } else if (fragmentIndex >= 0) {
      cutIndex = fragmentIndex;
    }
    if (cutIndex >= 0) {
      sanitized = sanitized.substring(0, cutIndex);
    }
    return _capAndRedact(sanitized, cap);
  }

  String? _capAndRedact(String? value, int cap) {
    if (value == null || value.isEmpty) return value;
    var sanitized = value;
    sanitized = sanitized.replaceAllMapped(
      RegExp(
        r'\b(cookie|authorization|token|password|session|account)\s*[:=]\s*([^\s,;]+)',
        caseSensitive: false,
      ),
      (match) => '${match.group(1)}=<redacted>',
    );
    if (sanitized.length > cap) {
      sanitized = sanitized.substring(0, cap);
    }
    return sanitized;
  }
}

final ReaderTraceRecorder readerTraceRecorder = ReaderTraceRecorder();

class ReaderSourceRefSnapshot {
  const ReaderSourceRefSnapshot({
    required this.id,
    required this.type,
    required this.sourceKey,
    required this.refId,
    this.routeKey,
    this.params = const {},
  });

  final String id;
  final String type;
  final String sourceKey;
  final String refId;
  final String? routeKey;
  final Map<String, Object?> params;

  Map<String, dynamic> toJson(ReaderTraceRecorder recorder) {
    return {
      'id': recorder._capAndRedact(id, 200),
      'type': recorder._capAndRedact(type, 80),
      'sourceKey': recorder._capAndRedact(sourceKey, 160),
      'refId': recorder._capAndRedact(refId, 160),
      'routeKey': recorder._capAndRedact(routeKey, 160),
      'params': params.map(
        (key, value) => MapEntry(
          key,
          value is String ? recorder._capAndRedact(value, 160) : value,
        ),
      ),
    };
  }
}
