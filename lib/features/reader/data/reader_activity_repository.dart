import 'dart:convert';

import 'package:venera/foundation/db/store_records.dart'
    show ReaderActivityRecord;
import 'package:venera/foundation/ports/comic_detail_store_port.dart';
import 'package:venera/foundation/ports/reader_activity_store_port.dart';
import 'package:venera/features/reader/data/reader_activity_models.dart';
import 'package:venera/foundation/source_ref.dart';

class ReaderActivityRepository {
  const ReaderActivityRepository({required this.store, this.comicDetailStore});

  final ReaderActivityStorePort store;
  final ComicDetailStorePort? comicDetailStore;

  Future<List<ReaderActivityItem>> loadRecent({int limit = 20}) async {
    final records = await store.loadReaderActivity(limit: limit);
    return _mapRecords(records);
  }

  Future<List<ReaderActivityItem>> loadAll() async {
    final records = await store.loadReaderActivity();
    return _mapRecords(records);
  }

  Future<int> count() {
    return store.countReaderActivity();
  }

  Future<void> remove(String comicId) {
    return store.deleteReaderActivity(comicId);
  }

  Future<void> clear() {
    return store.clearReaderActivity();
  }

  Future<List<ReaderActivityItem>> _mapRecords(
    List<ReaderActivityRecord> records,
  ) async {
    final mapped = <ReaderActivityItem>[];
    for (final record in records) {
      mapped.add(await _mapRecord(record));
    }
    return List.unmodifiable(mapped);
  }

  Future<ReaderActivityItem> _mapRecord(ReaderActivityRecord record) async {
    final sourceRef = SourceRef.fromJson(
      Map<String, dynamic>.from(jsonDecode(record.sourceRefJson) as Map),
    );
    final cover = await _canonicalizeLocalCover(
      sourceRef: sourceRef,
      fallbackCover: record.cover,
      comicId: record.comicId,
    );
    return ReaderActivityItem(
      comicId: record.comicId,
      title: record.title,
      subtitle: record.subtitle,
      cover: cover,
      sourceKey: sourceRef.sourceKey,
      sourceRef: sourceRef,
      chapterId: record.chapterId,
      pageIndex: record.pageIndex,
      lastReadAt: DateTime.parse(record.lastReadAt),
    );
  }

  Future<String> _canonicalizeLocalCover({
    required SourceRef sourceRef,
    required String fallbackCover,
    required String comicId,
  }) async {
    if (sourceRef.type != SourceRefType.local) {
      return fallbackCover;
    }
    if (fallbackCover.startsWith('file://')) {
      return fallbackCover;
    }
    final detailStore = comicDetailStore;
    if (detailStore == null) {
      return fallbackCover;
    }
    final snapshot = await detailStore.loadComicSnapshot(comicId);
    final coverPath = snapshot?.comic.coverLocalPath;
    if (coverPath == null || coverPath.isEmpty) {
      return fallbackCover;
    }
    return Uri.file(coverPath).toString();
  }
}
