import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:venera/foundation/comic_type.dart';
import 'package:venera/foundation/diagnostics/diagnostics.dart';
import 'package:venera/foundation/reader/reader_trace_recorder.dart';
import 'package:venera/foundation/sources/source_ref.dart';

class ReaderDiagnostics {
  ReaderDiagnostics._();

  static int _nextCallId = 0;
  static final Map<String, DateTime> _callStarts = {};
  static final Map<String, String> _callCorrelationIds = {};
  static final Map<String, DateTime> _pendingProviderSubscriptions = {};
  static final Map<String, Set<String>> _pendingProviderKeysByImageKey = {};
  static final Map<String, _ImageLifecycleState> _imageLifecycleByKey = {};

  static Map<String, dynamic> toDiagnosticsJson() {
    return readerTraceRecorder.toDiagnosticsJson();
  }

  static String beginCall({
    required String functionName,
    required ReaderTracePhase phase,
    String? loadMode,
    String? sourceKey,
    String? sourceRefId,
    String? comicId,
    String? chapterId,
    int? chapterIndex,
    int? page,
    String? imageKey,
  }) {
    final callId = '${DateTime.now().microsecondsSinceEpoch}-${_nextCallId++}';
    final correlationId = _buildCorrelationId(
      functionName: functionName,
      phase: phase,
      loadMode: loadMode,
      sourceKey: sourceKey,
      sourceRefId: sourceRefId,
      comicId: comicId,
      chapterId: chapterId,
    );
    _callStarts[callId] = DateTime.now();
    _callCorrelationIds[callId] = correlationId;
    readerTraceRecorder.record(
      ReaderTraceEvent(
        event: 'call.start',
        timestamp: DateTime.now(),
        phase: phase,
        functionName: functionName,
        callId: callId,
        loadMode: loadMode,
        sourceKey: sourceKey,
        comicId: comicId,
        chapterId: chapterId,
        chapterIndex: chapterIndex,
        page: page,
        imageKey: imageKey,
      ),
    );
    AppDiagnostics.trace(
      'reader.load',
      'call.start',
      data: {
        'functionName': functionName,
        'phase': phase.name,
        'callId': callId,
        'loadMode': loadMode,
        'sourceKey': sourceKey,
        'comicId': comicId,
        'chapterId': chapterId,
        'chapterIndex': chapterIndex,
        'page': page,
        'imageKey': imageKey,
        'correlationId': correlationId,
      },
    );
    return callId;
  }

  static void endCall({
    required String callId,
    required String functionName,
    required ReaderTracePhase phase,
    String? loadMode,
    String? sourceKey,
    String? sourceRefId,
    String? comicId,
    String? chapterId,
    int? chapterIndex,
    int? page,
    String? resultSummary,
  }) {
    final durationMs = _durationMs(callId);
    final correlationId = _resolveCorrelationId(
      callId: callId,
      functionName: functionName,
      phase: phase,
      loadMode: loadMode,
      sourceKey: sourceKey,
      sourceRefId: sourceRefId,
      comicId: comicId,
      chapterId: chapterId,
    );
    readerTraceRecorder.record(
      ReaderTraceEvent(
        event: 'call.end',
        timestamp: DateTime.now(),
        phase: phase,
        functionName: functionName,
        callId: callId,
        durationMs: durationMs,
        loadMode: loadMode,
        sourceKey: sourceKey,
        comicId: comicId,
        chapterId: chapterId,
        chapterIndex: chapterIndex,
        page: page,
        resultSummary: resultSummary,
      ),
    );
    AppDiagnostics.info(
      'reader.load',
      'call.end',
      data: {
        'functionName': functionName,
        'phase': phase.name,
        'callId': callId,
        'durationMs': durationMs,
        'loadMode': loadMode,
        'sourceKey': sourceKey,
        'comicId': comicId,
        'chapterId': chapterId,
        'chapterIndex': chapterIndex,
        'page': page,
        'resultSummary': resultSummary,
        'correlationId': correlationId,
      },
    );
    _callCorrelationIds.remove(callId);
  }

  static void failCall({
    required String callId,
    required String functionName,
    required ReaderTracePhase phase,
    required String errorMessage,
    String? errorCode,
    String? loadMode,
    String? sourceKey,
    String? sourceRefId,
    String? comicId,
    String? chapterId,
    int? chapterIndex,
    int? page,
    String? imageKey,
  }) {
    final durationMs = _durationMs(callId);
    final correlationId = _resolveCorrelationId(
      callId: callId,
      functionName: functionName,
      phase: phase,
      loadMode: loadMode,
      sourceKey: sourceKey,
      sourceRefId: sourceRefId,
      comicId: comicId,
      chapterId: chapterId,
    );
    readerTraceRecorder.record(
      ReaderTraceEvent(
        event: 'call.error',
        timestamp: DateTime.now(),
        phase: phase,
        functionName: functionName,
        callId: callId,
        durationMs: durationMs,
        loadMode: loadMode,
        sourceKey: sourceKey,
        comicId: comicId,
        chapterId: chapterId,
        chapterIndex: chapterIndex,
        page: page,
        imageKey: imageKey,
        errorCode: errorCode,
        errorMessage: errorMessage,
      ),
    );
    AppDiagnostics.warn(
      'reader.load',
      'call.error',
      data: {
        'functionName': functionName,
        'phase': phase.name,
        'callId': callId,
        'durationMs': durationMs,
        'loadMode': loadMode,
        'sourceKey': sourceKey,
        'comicId': comicId,
        'chapterId': chapterId,
        'chapterIndex': chapterIndex,
        'page': page,
        'imageKey': imageKey,
        'errorCode': errorCode,
        'errorMessage': errorMessage,
        'correlationId': correlationId,
      },
    );
    _callCorrelationIds.remove(callId);
  }

  static void updateReaderState({
    required String lifecycle,
    required ComicType type,
    required String comicId,
    required int chapterIndex,
    required int page,
    required String mode,
    required bool isLoading,
    required int? imageCount,
    required int? maxPage,
    required int? imagesPerPage,
    String? chapterId,
    String? sourceKey,
    String? loadMode,
    SourceRef? sourceRef,
  }) {
    final resolvedLoadMode =
        loadMode ?? (type == ComicType.local ? 'local' : 'remote');
    final resolvedSourceKey = sourceKey ?? type.sourceKey;
    readerTraceRecorder.updateReaderState(
      lifecycle: lifecycle,
      loadMode: resolvedLoadMode,
      sourceKey: resolvedSourceKey,
      comicId: comicId,
      chapterId: chapterId,
      chapterIndex: chapterIndex,
      page: page,
      mode: mode,
      isLoading: isLoading,
      imageCount: imageCount,
      maxPage: maxPage,
      imagesPerPage: imagesPerPage,
      sourceRef: sourceRef == null
          ? null
          : ReaderSourceRefSnapshot(
              id: sourceRef.id,
              type: sourceRef.type.key,
              sourceKey: sourceRef.sourceKey,
              refId: sourceRef.refId,
              routeKey: sourceRef.routeKey,
              params: sourceRef.params,
            ),
    );
    AppDiagnostics.trace(
      'reader.lifecycle',
      lifecycle,
      data: {
        'loadMode': resolvedLoadMode,
        'sourceKey': resolvedSourceKey,
        'comicId': comicId,
        'chapterId': chapterId,
        'chapterIndex': chapterIndex,
        'page': page,
        'mode': mode,
        'isLoading': isLoading,
        'imageCount': imageCount,
        'maxPage': maxPage,
        'imagesPerPage': imagesPerPage,
      },
    );
  }

  static void recordReaderLifecycle({
    required String event,
    required ComicType type,
    required String comicId,
    required int chapterIndex,
    required int page,
    String? chapterId,
    String? sourceKey,
    String? loadMode,
    String? resultSummary,
    Map<String, Object?> data = const {},
  }) {
    final resolvedLoadMode =
        loadMode ?? (type == ComicType.local ? 'local' : 'remote');
    final resolvedSourceKey = sourceKey ?? type.sourceKey;
    readerTraceRecorder.record(
      ReaderTraceEvent(
        event: event,
        timestamp: DateTime.now(),
        loadMode: resolvedLoadMode,
        sourceKey: resolvedSourceKey,
        comicId: comicId,
        chapterId: chapterId,
        chapterIndex: chapterIndex,
        page: page,
        resultSummary: resultSummary,
        phase: ReaderTracePhase.sourceResolution,
      ),
    );
    AppDiagnostics.info(
      'reader.lifecycle',
      event,
      data: {
        'loadMode': resolvedLoadMode,
        'sourceKey': resolvedSourceKey,
        'comicId': comicId,
        'chapterId': chapterId,
        'chapterIndex': chapterIndex,
        'page': page,
        ...data,
      },
    );
  }

  static void recordCanonicalSessionEvent({
    required String event,
    required String loadMode,
    required String sourceKey,
    required String comicId,
    required String chapterId,
    required int chapterIndex,
    required int page,
    String? sessionId,
    String? tabId,
    String? pageOrderId,
    String? reason,
  }) {
    readerTraceRecorder.record(
      ReaderTraceEvent(
        event: event,
        timestamp: DateTime.now(),
        loadMode: loadMode,
        sourceKey: sourceKey,
        comicId: comicId,
        chapterId: chapterId,
        chapterIndex: chapterIndex,
        page: page,
        resultSummary: [
          if (sessionId != null) 'sessionId=$sessionId',
          if (tabId != null) 'tabId=$tabId',
          if (pageOrderId != null) 'pageOrderId=$pageOrderId',
          if (reason != null) 'reason=$reason',
        ].join(' '),
        phase: ReaderTracePhase.sourceResolution,
      ),
    );
    AppDiagnostics.info(
      'reader.session',
      event,
      data: {
        'loadMode': loadMode,
        'sourceKey': sourceKey,
        'comicId': comicId,
        'chapterId': chapterId,
        'chapterIndex': chapterIndex,
        'page': page,
        'sessionId': sessionId,
        'tabId': tabId,
        'pageOrderId': pageOrderId,
        'reason': reason,
      },
    );
  }

  static void recordResumeLookupEvent({
    required String event,
    required String comicId,
    required String sourceKey,
    required String loadMode,
    String? chapterId,
    int? page,
    String? tabId,
    String? sessionId,
    String? fallbackSource,
  }) {
    readerTraceRecorder.record(
      ReaderTraceEvent(
        event: event,
        timestamp: DateTime.now(),
        loadMode: loadMode,
        sourceKey: sourceKey,
        comicId: comicId,
        chapterId: chapterId,
        page: page,
        resultSummary: [
          if (sessionId != null) 'sessionId=$sessionId',
          if (tabId != null) 'tabId=$tabId',
          if (fallbackSource != null) 'fallbackSource=$fallbackSource',
        ].join(' '),
        phase: ReaderTracePhase.sourceResolution,
      ),
    );
    AppDiagnostics.info(
      'reader.session',
      event,
      data: {
        'comicId': comicId,
        'sourceKey': sourceKey,
        'loadMode': loadMode,
        'chapterId': chapterId,
        'page': page,
        'tabId': tabId,
        'sessionId': sessionId,
        'fallbackSource': fallbackSource,
      },
    );
  }

  static String beginPageListLoad({
    required String loadMode,
    required String sourceKey,
    required String comicId,
    required int chapterIndex,
    required int page,
    String? chapterId,
  }) {
    return beginCall(
      functionName: 'ReaderImages.loadPageList',
      phase: ReaderTracePhase.pageList,
      loadMode: loadMode,
      sourceKey: sourceKey,
      comicId: comicId,
      chapterId: chapterId,
      chapterIndex: chapterIndex,
      page: page,
    );
  }

  static void endPageListLoad({
    required String callId,
    required String loadMode,
    required SourceRef sourceRef,
    required String comicId,
    required int chapterIndex,
    required int page,
    required int pageCount,
    required String sourceKey,
    required String chapterId,
  }) {
    endCall(
      callId: callId,
      functionName: 'ReaderImages.loadPageList',
      phase: ReaderTracePhase.pageList,
      loadMode: loadMode,
      sourceKey: sourceKey,
      sourceRefId: sourceRef.id,
      comicId: comicId,
      chapterId: chapterId,
      chapterIndex: chapterIndex,
      page: page,
      resultSummary: pageCount == 0 ? 'emptyPageList' : 'pageCount=$pageCount',
    );
    recordPageListResult(
      event: pageCount == 0 ? 'emptyPageList' : 'pageList.load.success',
      loadMode: loadMode,
      sourceRef: sourceRef,
      comicId: comicId,
      chapterIndex: chapterIndex,
      page: page,
      sourceKey: sourceKey,
      chapterId: chapterId,
    );
  }

  static void failPageListLoad({
    required String callId,
    required String loadMode,
    required SourceRef sourceRef,
    required String comicId,
    required int chapterIndex,
    required int page,
    required String errorMessage,
    required String sourceKey,
    required String chapterId,
    String? errorCode,
  }) {
    failCall(
      callId: callId,
      functionName: 'ReaderImages.loadPageList',
      phase: ReaderTracePhase.pageList,
      errorMessage: errorMessage,
      errorCode: errorCode,
      loadMode: loadMode,
      sourceKey: sourceKey,
      sourceRefId: sourceRef.id,
      comicId: comicId,
      chapterId: chapterId,
      chapterIndex: chapterIndex,
      page: page,
    );
    recordPageListResult(
      event: errorCode == 'SOURCE_NOT_AVAILABLE'
          ? 'source.unavailable'
          : 'pageList.load.error',
      loadMode: loadMode,
      sourceRef: sourceRef,
      comicId: comicId,
      chapterIndex: chapterIndex,
      page: page,
      sourceKey: sourceKey,
      chapterId: chapterId,
      errorCode: errorCode,
      errorMessage: errorMessage,
    );
  }

  static void recordPageListResult({
    required String event,
    required String loadMode,
    required SourceRef sourceRef,
    required String comicId,
    required int chapterIndex,
    required int page,
    required String sourceKey,
    required String chapterId,
    String? errorCode,
    String? errorMessage,
  }) {
    readerTraceRecorder.record(
      ReaderTraceEvent(
        event: event,
        timestamp: DateTime.now(),
        loadMode: loadMode,
        sourceKey: sourceKey,
        comicId: comicId,
        chapterId: chapterId,
        chapterIndex: chapterIndex,
        page: page,
        errorCode: errorCode,
        errorMessage: errorMessage,
        phase: errorCode == 'SOURCE_NOT_AVAILABLE'
            ? ReaderTracePhase.sourceResolution
            : ReaderTracePhase.pageList,
      ),
    );
    final level = errorCode == null
        ? DiagnosticLevel.info
        : DiagnosticLevel.warn;
    final data = {
      'event': event,
      'loadMode': loadMode,
      'sourceKey': sourceKey,
      'comicId': comicId,
      'chapterId': chapterId,
      'chapterIndex': chapterIndex,
      'page': page,
      'errorCode': errorCode,
      'errorMessage': errorMessage,
    };
    switch (level) {
      case DiagnosticLevel.trace:
      case DiagnosticLevel.info:
        AppDiagnostics.info('reader.load', event, data: data);
      case DiagnosticLevel.warn:
        AppDiagnostics.warn('reader.load', event, data: data);
      case DiagnosticLevel.error:
        AppDiagnostics.error('reader.load', errorMessage ?? event, data: data);
    }
  }

  static void recordImageProviderCreated({
    required ComicType type,
    required String comicId,
    required String chapterId,
    required int chapterIndex,
    required int page,
    required String imageKey,
  }) {
    readerTraceRecorder.record(
      ReaderTraceEvent(
        event: 'image.provider.created',
        timestamp: DateTime.now(),
        loadMode: type == ComicType.local ? 'local' : 'remote',
        sourceKey: type.sourceKey,
        comicId: comicId,
        chapterId: chapterId,
        chapterIndex: chapterIndex,
        page: page,
        imageKey: imageKey,
        phase: ReaderTracePhase.imageProvider,
      ),
    );
    AppDiagnostics.trace(
      'reader.image',
      'image.provider.created',
      data: {
        'loadMode': type == ComicType.local ? 'local' : 'remote',
        'sourceKey': type.sourceKey,
        'comicId': comicId,
        'chapterId': chapterId,
        'chapterIndex': chapterIndex,
        'page': page,
        'imageKey': imageKey,
      },
    );
  }

  static void markImageProviderAwaitingSubscription({
    required String loadMode,
    required String? sourceKey,
    required String comicId,
    required String chapterId,
    required int page,
    required String imageKey,
    String? providerTrackingKey,
  }) {
    final now = DateTime.now();
    final lifecycle = _imageLifecycleByKey.putIfAbsent(
      imageKey,
      _ImageLifecycleState.new,
    );
    lifecycle.providerCreatedAt = now;
    if (lifecycle.hasPreviousSuccessfulState) {
      return;
    }
    final key = _imageProviderSubscriptionKey(
      loadMode: loadMode,
      sourceKey: sourceKey,
      comicId: comicId,
      chapterId: chapterId,
      page: page,
      imageKey: imageKey,
      providerTrackingKey: providerTrackingKey,
    );
    _pendingProviderSubscriptions[key] = now;
    _pendingProviderKeysByImageKey
        .putIfAbsent(imageKey, () => <String>{})
        .add(key);
  }

  static void markImagePageAttached({required String imageKey}) {
    final lifecycle = _imageLifecycleByKey.putIfAbsent(
      imageKey,
      _ImageLifecycleState.new,
    );
    lifecycle.pageAttachedAt = DateTime.now();
    _clearPendingProviderSubscriptionsByImageKey(imageKey: imageKey);
  }

  static void markImageProviderLoadStarted({
    required String loadMode,
    required String? sourceKey,
    required String comicId,
    required String chapterId,
    required int page,
    required String imageKey,
    String? providerTrackingKey,
  }) {
    final lifecycle = _imageLifecycleByKey.putIfAbsent(
      imageKey,
      _ImageLifecycleState.new,
    );
    lifecycle.providerLoadStartedAt = DateTime.now();
    _clearPendingProviderSubscription(
      loadMode: loadMode,
      sourceKey: sourceKey,
      comicId: comicId,
      chapterId: chapterId,
      page: page,
      imageKey: imageKey,
      providerTrackingKey: providerTrackingKey,
    );
    _clearPendingProviderSubscriptionsByImageKey(imageKey: imageKey);
  }

  static void markImageProviderLoadSucceeded({required String imageKey}) {
    final lifecycle = _imageLifecycleByKey.putIfAbsent(
      imageKey,
      _ImageLifecycleState.new,
    );
    lifecycle.providerLoadSucceededAt = DateTime.now();
    lifecycle.hasPreviousSuccessfulState = true;
    _clearPendingProviderSubscriptionsByImageKey(imageKey: imageKey);
  }

  static void markImageProviderSubscriptionObserved({
    required String imageKey,
  }) {
    final lifecycle = _imageLifecycleByKey.putIfAbsent(
      imageKey,
      _ImageLifecycleState.new,
    );
    lifecycle.decodeSucceededAt = DateTime.now();
    lifecycle.hasPreviousSuccessfulState = true;
    _clearPendingProviderSubscriptionsByImageKey(imageKey: imageKey);
  }

  static void _clearPendingProviderSubscription({
    required String loadMode,
    required String? sourceKey,
    required String comicId,
    required String chapterId,
    required int page,
    required String imageKey,
    String? providerTrackingKey,
  }) {
    final key = _imageProviderSubscriptionKey(
      loadMode: loadMode,
      sourceKey: sourceKey,
      comicId: comicId,
      chapterId: chapterId,
      page: page,
      imageKey: imageKey,
      providerTrackingKey: providerTrackingKey,
    );
    _pendingProviderSubscriptions.remove(key);
    final keysForImage = _pendingProviderKeysByImageKey[imageKey];
    if (keysForImage == null) {
      return;
    }
    keysForImage.remove(key);
    if (keysForImage.isEmpty) {
      _pendingProviderKeysByImageKey.remove(imageKey);
    }
  }

  static void _clearPendingProviderSubscriptionsByImageKey({
    required String imageKey,
  }) {
    final keysForImage = _pendingProviderKeysByImageKey.remove(imageKey);
    if (keysForImage == null || keysForImage.isEmpty) {
      return;
    }
    for (final key in keysForImage) {
      _pendingProviderSubscriptions.remove(key);
    }
  }

  static bool recordProviderNotSubscribedIfPending({
    required String loadMode,
    required String? sourceKey,
    required String comicId,
    required String chapterId,
    required int page,
    required String imageKey,
    required String owner,
    String? providerTrackingKey,
  }) {
    final key = _imageProviderSubscriptionKey(
      loadMode: loadMode,
      sourceKey: sourceKey,
      comicId: comicId,
      chapterId: chapterId,
      page: page,
      imageKey: imageKey,
      providerTrackingKey: providerTrackingKey,
    );
    final createdAt = _pendingProviderSubscriptions.remove(key);
    final keysForImage = _pendingProviderKeysByImageKey[imageKey];
    keysForImage?.remove(key);
    if (keysForImage != null && keysForImage.isEmpty) {
      _pendingProviderKeysByImageKey.remove(imageKey);
    }
    if (createdAt == null) {
      return false;
    }
    final lifecycle = _imageLifecycleByKey[imageKey];
    if (_shouldSuppressProviderNotSubscribed(
      lifecycle: lifecycle,
      providerCreatedAt: createdAt,
    )) {
      return false;
    }
    final elapsedMs = DateTime.now().difference(createdAt).inMilliseconds;
    readerTraceRecorder.record(
      ReaderTraceEvent(
        event: 'image.provider.notSubscribed',
        timestamp: DateTime.now(),
        loadMode: loadMode,
        sourceKey: sourceKey,
        comicId: comicId,
        chapterId: chapterId,
        page: page,
        imageKey: imageKey,
        errorCode: 'PROVIDER_NOT_SUBSCRIBED',
        resultSummary: 'owner=$owner elapsedMs=$elapsedMs',
        phase: ReaderTracePhase.imageProvider,
      ),
    );
    AppDiagnostics.warn(
      'reader.render',
      'reader.render.provider.notSubscribed',
      data: {
        'code': 'PROVIDER_NOT_SUBSCRIBED',
        'owner': owner,
        'elapsedMs': elapsedMs,
        'loadMode': loadMode,
        'sourceKey': sourceKey,
        'comicId': comicId,
        'chapterId': chapterId,
        'page': page,
        'imageKey': imageKey,
      },
    );
    return true;
  }

  @visibleForTesting
  static void clearPendingProviderSubscriptionsForTesting() {
    _pendingProviderSubscriptions.clear();
    _pendingProviderKeysByImageKey.clear();
    _imageLifecycleByKey.clear();
  }

  static bool _shouldSuppressProviderNotSubscribed({
    required _ImageLifecycleState? lifecycle,
    required DateTime providerCreatedAt,
  }) {
    if (lifecycle == null) {
      return false;
    }
    if (lifecycle.hasPreviousSuccessfulState) {
      return true;
    }
    return _isNearOrAfter(
          moment: lifecycle.pageAttachedAt,
          reference: providerCreatedAt,
        ) ||
        _isNearOrAfter(
          moment: lifecycle.providerLoadStartedAt,
          reference: providerCreatedAt,
        ) ||
        _isNearOrAfter(
          moment: lifecycle.providerLoadSucceededAt,
          reference: providerCreatedAt,
        ) ||
        _isNearOrAfter(
          moment: lifecycle.decodeSucceededAt,
          reference: providerCreatedAt,
        );
  }

  static bool _isNearOrAfter({
    required DateTime? moment,
    required DateTime reference,
  }) {
    if (moment == null) {
      return false;
    }
    final lowerBound = reference.subtract(const Duration(milliseconds: 250));
    return !moment.isBefore(lowerBound);
  }

  static String beginImageLoad({
    required String loadMode,
    required String? sourceKey,
    required String comicId,
    required String chapterId,
    required int page,
    required String imageKey,
    String? providerTrackingKey,
  }) {
    markImageProviderLoadStarted(
      loadMode: loadMode,
      sourceKey: sourceKey,
      comicId: comicId,
      chapterId: chapterId,
      page: page,
      imageKey: imageKey,
      providerTrackingKey: providerTrackingKey,
    );
    return beginCall(
      functionName: 'ReaderImageProvider.load',
      phase: ReaderTracePhase.imageProvider,
      loadMode: loadMode,
      sourceKey: sourceKey,
      comicId: comicId,
      chapterId: chapterId,
      page: page,
      imageKey: imageKey,
    );
  }

  static String _imageProviderSubscriptionKey({
    required String loadMode,
    required String? sourceKey,
    required String comicId,
    required String chapterId,
    required int page,
    required String imageKey,
    String? providerTrackingKey,
  }) {
    if (providerTrackingKey != null && providerTrackingKey.isNotEmpty) {
      return providerTrackingKey;
    }
    return '$loadMode|${sourceKey ?? ''}|$comicId|$chapterId|$page|$imageKey';
  }

  static void endImageLoad({
    required String callId,
    required String loadMode,
    required String? sourceKey,
    required String comicId,
    required String chapterId,
    required int page,
    required String imageKey,
    required int byteLength,
  }) {
    endCall(
      callId: callId,
      functionName: 'ReaderImageProvider.load',
      phase: ReaderTracePhase.imageProvider,
      loadMode: loadMode,
      sourceKey: sourceKey,
      comicId: comicId,
      chapterId: chapterId,
      page: page,
      resultSummary: 'bytes=$byteLength',
    );
    markImageProviderLoadSucceeded(imageKey: imageKey);
  }

  static void failImageLoad({
    required String callId,
    required String loadMode,
    required String? sourceKey,
    required String comicId,
    required String chapterId,
    required int page,
    required String imageKey,
    required Object error,
  }) {
    failCall(
      callId: callId,
      functionName: 'ReaderImageProvider.load',
      phase: ReaderTracePhase.imageProvider,
      errorMessage: error.toString(),
      loadMode: loadMode,
      sourceKey: sourceKey,
      comicId: comicId,
      chapterId: chapterId,
      page: page,
      imageKey: imageKey,
    );
  }

  static void recordImageLoadError({
    required Object error,
    String? imageKey,
    String? sourceKey,
    String? comicId,
    String? chapterId,
    int? page,
  }) {
    readerTraceRecorder.record(
      ReaderTraceEvent(
        event: 'image.load.error',
        timestamp: DateTime.now(),
        imageKey: imageKey,
        sourceKey: sourceKey,
        comicId: comicId,
        chapterId: chapterId,
        page: page,
        errorMessage: error.toString(),
        phase: ReaderTracePhase.decode,
      ),
    );
    AppDiagnostics.error(
      'reader.decode',
      error,
      data: {
        'sourceKey': sourceKey,
        'comicId': comicId,
        'chapterId': chapterId,
        'page': page,
        'imageKey': imageKey,
      },
    );
  }

  static void recordImageDecodeSuccess({
    required String imageKey,
    required String? sourceKey,
    required String comicId,
    required String chapterId,
    required int page,
    required int byteLength,
  }) {
    readerTraceRecorder.record(
      ReaderTraceEvent(
        event: 'image.decode.success',
        timestamp: DateTime.now(),
        imageKey: imageKey,
        sourceKey: sourceKey,
        comicId: comicId,
        chapterId: chapterId,
        page: page,
        resultSummary: 'bytes=$byteLength',
        phase: ReaderTracePhase.decode,
      ),
    );
    AppDiagnostics.trace(
      'reader.decode',
      'image.decode.success',
      data: {
        'sourceKey': sourceKey,
        'comicId': comicId,
        'chapterId': chapterId,
        'page': page,
        'imageKey': imageKey,
        'byteLength': byteLength,
      },
    );
    markImageProviderSubscriptionObserved(imageKey: imageKey);
  }

  static void recordImageDecodeError({
    required String imageKey,
    required String? sourceKey,
    required String comicId,
    required String chapterId,
    required int page,
    required Object error,
  }) {
    readerTraceRecorder.record(
      ReaderTraceEvent(
        event: 'image.decode.error',
        timestamp: DateTime.now(),
        imageKey: imageKey,
        sourceKey: sourceKey,
        comicId: comicId,
        chapterId: chapterId,
        page: page,
        errorMessage: error.toString(),
        phase: ReaderTracePhase.decode,
      ),
    );
    AppDiagnostics.error(
      'reader.decode',
      error,
      data: {
        'sourceKey': sourceKey,
        'comicId': comicId,
        'chapterId': chapterId,
        'page': page,
        'imageKey': imageKey,
      },
    );
  }

  static void recordImageFrameRendered({
    required String imageKey,
    required String? sourceKey,
    required String comicId,
    required String chapterId,
    required int page,
    required int frameNumber,
    required bool synchronousCall,
    required String widgetType,
  }) {
    readerTraceRecorder.record(
      ReaderTraceEvent(
        event: 'image.frame.rendered',
        timestamp: DateTime.now(),
        imageKey: imageKey,
        sourceKey: sourceKey,
        comicId: comicId,
        chapterId: chapterId,
        page: page,
        resultSummary:
            'frame=$frameNumber sync=$synchronousCall widget=$widgetType',
        phase: ReaderTracePhase.decode,
      ),
    );
    AppDiagnostics.trace(
      'reader.decode',
      'image.frame.rendered',
      data: {
        'sourceKey': sourceKey,
        'comicId': comicId,
        'chapterId': chapterId,
        'page': page,
        'imageKey': imageKey,
        'frameNumber': frameNumber,
        'synchronousCall': synchronousCall,
        'widgetType': widgetType,
      },
    );
  }

  static int? _durationMs(String callId) {
    final start = _callStarts.remove(callId);
    if (start == null) {
      return null;
    }
    return DateTime.now().difference(start).inMilliseconds;
  }

  static String _resolveCorrelationId({
    required String callId,
    required String functionName,
    required ReaderTracePhase phase,
    String? loadMode,
    String? sourceKey,
    String? sourceRefId,
    String? comicId,
    String? chapterId,
  }) {
    final existing = _callCorrelationIds[callId];
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }
    return _buildCorrelationId(
      functionName: functionName,
      phase: phase,
      loadMode: loadMode,
      sourceKey: sourceKey,
      sourceRefId: sourceRefId,
      comicId: comicId,
      chapterId: chapterId,
    );
  }

  static String _buildCorrelationId({
    required String functionName,
    required ReaderTracePhase phase,
    String? loadMode,
    String? sourceKey,
    String? sourceRefId,
    String? comicId,
    String? chapterId,
  }) {
    final normalizedRef = _normalizeCorrelationPart(sourceRefId);
    final normalizedContext = [
      _normalizeCorrelationPart(loadMode),
      _normalizeCorrelationPart(sourceKey),
      _normalizeCorrelationPart(comicId),
      _normalizeCorrelationPart(chapterId),
    ].whereType<String>().join('|');
    final keyPart = normalizedRef != null && normalizedRef.isNotEmpty
        ? 'ref:$normalizedRef'
        : 'ctx:$normalizedContext';
    return [
      _normalizeCorrelationPart(functionName) ?? 'unknownFunction',
      _normalizeCorrelationPart(phase.name) ?? 'unknownPhase',
      keyPart,
    ].join('::');
  }

  static String? _normalizeCorrelationPart(String? value) {
    if (value == null) {
      return null;
    }
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    return trimmed.replaceAll(RegExp(r'\s+'), '_');
  }
}

class _ImageLifecycleState {
  DateTime? providerCreatedAt;
  DateTime? pageAttachedAt;
  DateTime? providerLoadStartedAt;
  DateTime? providerLoadSucceededAt;
  DateTime? decodeSucceededAt;
  bool hasPreviousSuccessfulState = false;
}
