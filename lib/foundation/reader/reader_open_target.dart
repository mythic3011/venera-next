import 'package:venera/features/sources/comic_source/comic_source.dart';
import 'package:venera/foundation/sources/identity/constants.dart';
import 'package:venera/foundation/sources/source_ref.dart';

const String _localImportedFallbackChapterSuffix = '__imported__';

class ReaderOpenTarget {
  const ReaderOpenTarget({required this.sourceRef});

  final SourceRef sourceRef;

  String? get chapterId => sourceRef.params['chapterId']?.toString();
}

String? resolveReaderTargetChapterId({
  required ComicChapters? chapters,
  required int? ep,
  required int? group,
}) {
  if (chapters == null || ep == null || ep < 1) {
    return null;
  }

  var chapterIndex = ep - 1;
  if (group != null && group > 1 && chapters.isGrouped) {
    for (int i = 0; i < group - 1; i++) {
      chapterIndex += chapters.getGroupByIndex(i).length;
    }
  }
  return chapters.ids.elementAtOrNull(chapterIndex);
}

SourceRef resolveReaderTargetSourceRef({
  required String comicId,
  required String sourceKey,
  required ComicChapters? chapters,
  required int? ep,
  required int? group,
  required ReaderOpenTarget? resumeTarget,
}) {
  final targetChapterId =
      resolveReaderTargetChapterId(chapters: chapters, ep: ep, group: group) ??
      _resolveLocalFallbackChapterId(comicId: comicId, sourceKey: sourceKey, chapters: chapters);
  final sourceRef =
      resumeTarget?.sourceRef ??
      SourceRef.fromLegacy(
        comicId: comicId,
        sourceKey: sourceKey,
        chapterId: targetChapterId,
      );
  if (targetChapterId == null ||
      sourceRef.params['chapterId']?.toString() == targetChapterId) {
    return sourceRef;
  }
  return switch (sourceRef.type) {
    SourceRefType.local => SourceRef.fromLegacyLocal(
      localType: sourceRef.params['localType']?.toString() ?? 'local',
      localComicId: sourceRef.params['localComicId']?.toString() ?? comicId,
      chapterId: targetChapterId,
    ),
    SourceRefType.remote => SourceRef.fromLegacyRemote(
      sourceKey: sourceRef.sourceKey,
      comicId: sourceRef.params['comicId']?.toString() ?? comicId,
      chapterId: targetChapterId,
      routeKey: sourceRef.routeKey,
    ),
  };
}

String? _resolveLocalFallbackChapterId({
  required String comicId,
  required String sourceKey,
  required ComicChapters? chapters,
}) {
  if (sourceKey != localSourceKey || chapters != null) {
    return null;
  }
  return '$comicId:$_localImportedFallbackChapterSuffix';
}
