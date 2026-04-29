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
  final ReaderTracePhase phase;
}

class ReaderTraceRecorder {
  ReaderTraceRecorder({this.maxEvents = 100});

  final int maxEvents;
  final List<Map<String, dynamic>> _events = [];

  void clear() => _events.clear();

  void record(ReaderTraceEvent event) {
    if (_events.length >= maxEvents) {
      _events.removeAt(0);
    }
    _events.add(_toJson(event));
  }

  Map<String, dynamic> toDiagnosticsJson() {
    return {
      'readerTrace': {
        'maxEvents': maxEvents,
        'eventCount': _events.length,
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
