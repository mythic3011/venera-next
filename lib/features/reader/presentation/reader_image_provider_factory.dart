part of 'reader.dart';

ReaderImageProvider buildReaderImageProvider({
  required String imageKey,
  required SourceRef sourceRef,
  required String canonicalComicId,
  required String upstreamComicRefId,
  required String chapterRefId,
  required int page,
  required bool enableResize,
}) {
  recordReaderPageAttachedDiagnostic(
    imageKey: imageKey,
    sourceRef: sourceRef,
    canonicalComicId: canonicalComicId,
    chapterRefId: chapterRefId,
    page: page,
  );
  recordReaderProviderCreatedDiagnostic(
    imageKey: imageKey,
    sourceRef: sourceRef,
    canonicalComicId: canonicalComicId,
    chapterRefId: chapterRefId,
    page: page,
  );
  return ReaderImageProvider(
    imageKey,
    sourceRef,
    canonicalComicId,
    upstreamComicRefId,
    chapterRefId,
    page,
    enableResize: enableResize,
  );
}

ImageProvider _createImageProviderFromKey(
  String imageKey,
  BuildContext context,
  int page,
) {
  var reader = context.reader;
  final runtimeContext = reader.currentReaderContext(pageOverride: page);
  reader.recordImageProviderDiagnostics(imageKey: imageKey, imagePage: page);
  return buildReaderImageProvider(
    imageKey: imageKey,
    sourceRef: runtimeContext.sourceRef,
    canonicalComicId: runtimeContext.canonicalComicId,
    upstreamComicRefId: runtimeContext.sourceRef.refId,
    chapterRefId: runtimeContext.chapterId,
    page: page,
    enableResize: reader.mode.isContinuous,
  );
}

ImageProvider _createImageProvider(int page, BuildContext context) {
  var reader = context.reader;
  var imageKey = reader.images![page - 1];
  return _createImageProviderFromKey(imageKey, context, page);
}
