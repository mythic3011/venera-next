part of 'reader.dart';

void recordReaderPageAttachedDiagnostic({
  required String imageKey,
  required SourceRef sourceRef,
  required String canonicalComicId,
  required String chapterRefId,
  required int page,
}) {
  final loadMode = imageKey.startsWith('file://') ? 'local' : 'remote';
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
}) {
  final loadMode = imageKey.startsWith('file://') ? 'local' : 'remote';
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
