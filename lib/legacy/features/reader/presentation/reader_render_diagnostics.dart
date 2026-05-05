part of 'reader.dart';

int _readerProviderTrackingCounter = 0;

String allocateReaderProviderTrackingKeyForTesting() {
  _readerProviderTrackingCounter++;
  return 'reader-provider-$_readerProviderTrackingCounter';
}

void recordReaderPageAttachedDiagnostic({
  required String imageKey,
  required SourceRef sourceRef,
  required String canonicalComicId,
  required String chapterRefId,
  required int page,
}) {
  final loadMode = imageKey.startsWith('file://') ? 'local' : 'remote';
  ReaderDiagnostics.markImagePageAttached(imageKey: imageKey);
  AppDiagnostics.trace(
    'reader.render',
    'reader.render.page.attached',
    data: {
      'loadMode': loadMode,
      'sourceKey': sourceRef.sourceKey,
      'comicId': canonicalComicId,
      'chapterId': chapterRefId,
      'page': page,
      'imageKey': imageKey,
    },
  );
}

void recordReaderProviderCreatedDiagnostic({
  required String imageKey,
  required SourceRef sourceRef,
  required String canonicalComicId,
  required String chapterRefId,
  required int page,
  required String providerTrackingKey,
}) {
  final loadMode = imageKey.startsWith('file://') ? 'local' : 'remote';
  ReaderDiagnostics.markImageProviderAwaitingSubscription(
    loadMode: loadMode,
    sourceKey: sourceRef.sourceKey,
    comicId: canonicalComicId,
    chapterId: chapterRefId,
    page: page,
    imageKey: imageKey,
    providerTrackingKey: providerTrackingKey,
  );
  AppDiagnostics.trace(
    'reader.render',
    'reader.render.page.provider.created',
    data: {
      'loadMode': loadMode,
      'sourceKey': sourceRef.sourceKey,
      'comicId': canonicalComicId,
      'chapterId': chapterRefId,
      'page': page,
      'imageKey': imageKey,
    },
  );
  AppDiagnostics.trace(
    'reader.render',
    'reader.render.provider.created',
    data: {
      'loadMode': loadMode,
      'sourceKey': sourceRef.sourceKey,
      'comicId': canonicalComicId,
      'chapterId': chapterRefId,
      'page': page,
      'imageKey': imageKey,
    },
  );
  SchedulerBinding.instance.addPostFrameCallback((_) {
    Future<void>.delayed(const Duration(milliseconds: 50), () {
      ReaderDiagnostics.recordProviderNotSubscribedIfPending(
        loadMode: loadMode,
        sourceKey: sourceRef.sourceKey,
        comicId: canonicalComicId,
        chapterId: chapterRefId,
        page: page,
        imageKey: imageKey,
        owner: 'reader.render.postFrame',
        providerTrackingKey: providerTrackingKey,
      );
    });
  });
}

void recordReaderRenderBlockedDiagnostic({
  required String code,
  required String loadMode,
  required String sourceKey,
  required String canonicalComicId,
  required String chapterRefId,
  required String imageKey,
  String? upstreamComicRefId,
  String? fileName,
}) {
  AppDiagnostics.warn(
    'reader.render',
    'reader.render.blocked',
    data: {
      'code': code,
      'loadMode': loadMode,
      'sourceKey': sourceKey,
      'comicId': canonicalComicId,
      'chapterId': chapterRefId,
      'imageKey': imageKey,
      if (upstreamComicRefId != null) 'upstreamComicRefId': upstreamComicRefId,
      if (fileName != null) 'fileName': fileName,
    },
  );
}

void recordReaderProviderFailedDiagnostic({
  required String code,
  required String loadMode,
  required String sourceKey,
  required String canonicalComicId,
  required String chapterRefId,
  required String imageKey,
  String? upstreamComicRefId,
  String? fileName,
}) {
  AppDiagnostics.warn(
    'reader.render',
    'reader.render.provider.failed',
    data: {
      'code': code,
      'loadMode': loadMode,
      'sourceKey': sourceKey,
      'comicId': canonicalComicId,
      'chapterId': chapterRefId,
      'imageKey': imageKey,
      if (upstreamComicRefId != null) 'upstreamComicRefId': upstreamComicRefId,
      if (fileName != null) 'fileName': fileName,
    },
  );
}
