part of '../local.dart';

String localPageImageKey(File file) => file.uri.toString();

ReaderOpenRequest buildLocalComicReaderOpenRequest({
  required LocalComic comic,
  required History? history,
  required int? firstDownloadedChapter,
  required int? firstDownloadedChapterGroup,
  required SourceRef? resumeSourceRef,
  String? diagnosticEntrypoint,
  String? diagnosticCaller,
}) {
  final sourceRef = resolveReaderTargetSourceRef(
    comicId: comic.id,
    sourceKey: comic.comicType.sourceKey,
    chapters: comic.chapters,
    ep: history?.ep ?? firstDownloadedChapter,
    group: history?.group ?? firstDownloadedChapterGroup,
    resumeSourceRef: resumeSourceRef,
  );
  return ReaderOpenRequest(
    comicId: comic.id,
    sourceRef: sourceRef,
    sourceKey: sourceRef.sourceKey,
    initialEp: history?.ep ?? firstDownloadedChapter,
    initialPage: history?.page,
    initialGroup: history?.group ?? firstDownloadedChapterGroup,
    diagnosticEntrypoint: diagnosticEntrypoint,
    diagnosticCaller: diagnosticCaller,
  );
}

class LocalComic with HistoryMixin implements Comic {
  @override
  final String id;

  @override
  final String title;

  @override
  final String subtitle;

  @override
  final List<String> tags;

  /// The name of the directory where the comic is stored
  final String directory;

  /// key: chapter id, value: chapter title
  ///
  /// chapter id is the name of the directory in `LocalManager.path/$directory`
  final ComicChapters? chapters;

  bool get hasChapters => chapters != null;

  /// relative path to the cover image
  @override
  final String cover;

  final ComicType comicType;

  final List<String> downloadedChapters;

  final DateTime createdAt;

  const LocalComic({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.tags,
    required this.directory,
    required this.chapters,
    required this.cover,
    required this.comicType,
    required this.downloadedChapters,
    required this.createdAt,
  });

  LocalComic.fromRow(Row row)
    : id = row[0] as String,
      title = row[1] as String,
      subtitle = row[2] as String,
      tags = List.from(jsonDecode(row[3] as String)),
      directory = row[4] as String,
      chapters = ComicChapters.fromJsonOrNull(jsonDecode(row[5] as String)),
      cover = row[6] as String,
      comicType = ComicType(row[7] as int),
      downloadedChapters = List.from(jsonDecode(row[8] as String)),
      createdAt = DateTime.fromMillisecondsSinceEpoch(row[9] as int);

  File get coverFile => File(FilePath.join(baseDir, cover));

  String get baseDir => (directory.contains('/') || directory.contains('\\'))
      ? directory
      : FilePath.join(LocalManager().path, directory);

  @override
  String get description => "";

  @override
  String get sourceKey =>
      comicType == ComicType.local ? "local" : comicType.sourceKey;

  @override
  Map<String, dynamic> toJson() {
    return {
      "title": title,
      "cover": cover,
      "id": id,
      "subTitle": subtitle,
      "tags": tags,
      "description": description,
      "sourceKey": sourceKey,
      "chapters": chapters?.toJson(),
    };
  }

  @override
  int? get maxPage => null;

  void read() async {
    try {
      await LocalComicCanonicalSyncService(
        store: App.unifiedComicsStore,
      ).syncComic(this);
    } catch (error) {
      App.rootContext.showMessage(message: error.toString());
      return;
    }
    var history = HistoryManager().find(id, comicType);
    int? firstDownloadedChapter;
    int? firstDownloadedChapterGroup;
    if (downloadedChapters.isNotEmpty && chapters != null) {
      final chapters = this.chapters!;
      if (chapters.isGrouped) {
        for (int i = 0; i < chapters.groupCount; i++) {
          var group = chapters.getGroupByIndex(i);
          var keys = group.keys.toList();
          for (int j = 0; j < keys.length; j++) {
            var chapterId = keys[j];
            if (downloadedChapters.contains(chapterId)) {
              firstDownloadedChapter = j + 1;
              firstDownloadedChapterGroup = i + 1;
              break;
            }
          }
        }
      } else {
        var keys = chapters.allChapters.keys;
        for (int i = 0; i < keys.length; i++) {
          if (downloadedChapters.contains(keys.elementAt(i))) {
            firstDownloadedChapter = i + 1;
            break;
          }
        }
      }
    }
    final request = buildLocalComicReaderOpenRequest(
      comic: this,
      history: history,
      firstDownloadedChapter: firstDownloadedChapter,
      firstDownloadedChapterGroup: firstDownloadedChapterGroup,
      resumeSourceRef: HistoryManager().findResumeSourceRef(id, comicType),
      diagnosticEntrypoint: 'local_comic.read',
      diagnosticCaller: 'LocalComic.read',
    );
    await const ReaderRouteDispatchAuthority().openLegacy(request);
  }

  @override
  HistoryType get historyType => comicType;

  @override
  String? get subTitle => subtitle;

  @override
  String? get language => null;

  @override
  String? get favoriteId => null;

  @override
  double? get stars => null;
}
