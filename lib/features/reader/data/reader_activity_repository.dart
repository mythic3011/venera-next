import 'dart:convert';

import 'package:venera/foundation/db/store_records.dart'
    show ReaderActivityRecord;
import 'package:venera/foundation/ports/reader_activity_store_port.dart';
import 'package:venera/features/reader/data/reader_activity_models.dart';
import 'package:venera/foundation/source_ref.dart';

class ReaderActivityRepository {
  const ReaderActivityRepository({required this.store});

  final ReaderActivityStorePort store;

  Future<List<ReaderActivityItem>> loadRecent({int limit = 20}) async {
    final records = await store.loadReaderActivity(limit: limit);
    return records.map(_mapRecord).toList(growable: false);
  }

  Future<List<ReaderActivityItem>> loadAll() async {
    final records = await store.loadReaderActivity();
    return records.map(_mapRecord).toList(growable: false);
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

  ReaderActivityItem _mapRecord(ReaderActivityRecord record) {
    final sourceRef = SourceRef.fromJson(
      Map<String, dynamic>.from(jsonDecode(record.sourceRefJson) as Map),
    );
    return ReaderActivityItem(
      comicId: record.comicId,
      title: record.title,
      subtitle: record.subtitle,
      cover: record.cover,
      sourceKey: sourceRef.sourceKey,
      sourceRef: sourceRef,
      chapterId: record.chapterId,
      pageIndex: record.pageIndex,
      lastReadAt: DateTime.parse(record.lastReadAt),
    );
  }
}
