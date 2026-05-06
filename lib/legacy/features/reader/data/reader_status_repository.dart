import 'dart:convert';

import 'package:venera/features/sources/comic_source/comic_source.dart';
import 'package:venera/foundation/comic_type.dart';
import 'package:venera/foundation/db/remote_comic_sync.dart';
import 'package:venera/foundation/history.dart';
import 'package:venera/foundation/ports/reader_status_store_port.dart';
import 'package:venera/foundation/sources/source_ref.dart';

String readerStatusMapKey({
  required String comicId,
  required String sourceKey,
}) {
  return '$sourceKey@@$comicId';
}

String canonicalComicIdForStatus({
  required String comicId,
  required String sourceKey,
}) {
  if (sourceKey == ComicType.local.sourceKey) {
    return comicId;
  }
  return canonicalRemoteComicId(sourceKey: sourceKey, comicId: comicId);
}

class ReaderComicStatus {
  const ReaderComicStatus({
    required this.isFavorite,
    this.sourceRef,
    this.chapterId,
    this.pageIndex,
    this.maxPage,
  });

  final bool isFavorite;
  final SourceRef? sourceRef;
  final String? chapterId;
  final int? pageIndex;
  final int? maxPage;

  History? buildCompatibilityHistory(Comic comic) {
    final page = pageIndex;
    if (page == null) {
      return null;
    }
    return History.fromMap({
      'type': ComicType.fromKey(comic.sourceKey).value,
      'time': DateTime.now().millisecondsSinceEpoch,
      'title': comic.title,
      'subtitle': comic.subtitle ?? '',
      'cover': comic.cover,
      'ep': 0,
      'page': page,
      'id': comic.id,
      'readEpisode': const <String>[],
      'max_page': maxPage,
    });
  }
}

class ReaderStatusRepository {
  const ReaderStatusRepository({required this.store});

  final ReaderStatusStorePort store;

  Future<Map<String, ReaderComicStatus>> loadStatusesForComics(
    List<Comic> comics,
  ) async {
    if (comics.isEmpty) {
      return const <String, ReaderComicStatus>{};
    }
    final byCanonicalId = <String, Comic>{};
    for (final comic in comics) {
      byCanonicalId[canonicalComicIdForStatus(
            comicId: comic.id,
            sourceKey: comic.sourceKey,
          )] =
          comic;
    }
    final records = await store.loadReaderStatusesForComics(
      byCanonicalId.keys.toList(growable: false),
    );
    final statuses = <String, ReaderComicStatus>{};
    records.forEach((canonicalId, record) {
      final comic = byCanonicalId[canonicalId];
      if (comic == null) {
        return;
      }
      final sourceRefJson = record.sourceRefJson;
      statuses[readerStatusMapKey(
        comicId: comic.id,
        sourceKey: comic.sourceKey,
      )] = ReaderComicStatus(
        isFavorite: record.isFavorite,
        sourceRef: sourceRefJson == null
            ? null
            : SourceRef.fromJson(
                Map<String, dynamic>.from(jsonDecode(sourceRefJson) as Map),
              ),
        chapterId: record.chapterId,
        pageIndex: record.pageIndex,
        maxPage: record.maxPage,
      );
    });
    return statuses;
  }
}
