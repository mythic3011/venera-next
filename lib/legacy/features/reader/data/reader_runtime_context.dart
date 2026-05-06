import 'package:flutter/foundation.dart';
import 'package:venera/foundation/comic_type.dart';
import 'package:venera/foundation/db/remote_comic_sync.dart';
import 'package:venera/foundation/sources/source_ref.dart';
import 'package:venera/foundation/sources/identity/constants.dart';

String _normalizeReaderChapterId(String? chapterId) {
  if (chapterId == null || chapterId.isEmpty) {
    return '0';
  }
  return chapterId;
}

String _canonicalReaderComicId({
  required String comicId,
  required SourceRef sourceRef,
}) {
  if (sourceRef.type == SourceRefType.local) {
    return comicId;
  }
  return canonicalRemoteComicId(
    sourceKey: sourceRef.sourceKey,
    comicId: sourceRef.refId,
  );
}

@visibleForTesting
String normalizeReaderChapterIdForTesting(String? chapterId) {
  return _normalizeReaderChapterId(chapterId);
}

class ReaderRuntimeContext {
  const ReaderRuntimeContext({
    required this.comicId,
    required this.canonicalComicId,
    required this.sourceKey,
    required this.chapterId,
    required this.chapterIndex,
    required this.page,
    required this.loadMode,
    required this.sourceRef,
  });

  final String comicId;
  final String canonicalComicId;
  final String sourceKey;
  final String chapterId;
  final int chapterIndex;
  final int page;
  final String loadMode;
  final SourceRef sourceRef;
}

ReaderRuntimeContext buildReaderRuntimeContext({
  required String comicId,
  required ComicType type,
  required int chapterIndex,
  required int page,
  required String? chapterId,
  required SourceRef sourceRef,
}) {
  final normalizedChapterId = _normalizeReaderChapterId(chapterId);
  final sourceKey = sourceRef.sourceKey.isNotEmpty
      ? sourceRef.sourceKey
      : (type == ComicType.local ? localSourceKey : type.sourceKey);
  return ReaderRuntimeContext(
    comicId: comicId,
    canonicalComicId: _canonicalReaderComicId(
      comicId: comicId,
      sourceRef: sourceRef,
    ),
    sourceKey: sourceKey,
    chapterId: normalizedChapterId,
    chapterIndex: chapterIndex,
    page: page,
    loadMode: sourceRef.type == SourceRefType.local ? 'local' : 'remote',
    sourceRef: sourceRef,
  );
}

@visibleForTesting
ReaderRuntimeContext buildReaderRuntimeContextForTesting({
  required String comicId,
  required ComicType type,
  required int chapterIndex,
  required int page,
  required String? chapterId,
  required SourceRef sourceRef,
}) {
  return buildReaderRuntimeContext(
    comicId: comicId,
    type: type,
    chapterIndex: chapterIndex,
    page: page,
    chapterId: chapterId,
    sourceRef: sourceRef,
  );
}
