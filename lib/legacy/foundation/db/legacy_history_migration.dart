import 'dart:io';

import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:venera/foundation/sources/identity/source_identity.dart';

import 'unified_comics_store.dart';

class LegacyHistoryMigrationReport {
  const LegacyHistoryMigrationReport({
    required this.sourceDbPath,
    required this.targetDbPath,
    required this.imported,
    required this.skippedMissingComic,
  });

  final String sourceDbPath;
  final String targetDbPath;
  final int imported;
  final int skippedMissingComic;
}

class LegacyHistoryMigrationService {
  const LegacyHistoryMigrationService();

  Future<LegacyHistoryMigrationReport> importHistoryDb({
    required UnifiedComicsStore store,
    required String legacyDbPath,
  }) async {
    final dbFile = File(legacyDbPath);
    if (!dbFile.existsSync()) {
      throw ArgumentError.value(legacyDbPath, 'legacyDbPath', 'File not found');
    }

    final legacyDb = sqlite.sqlite3.open(legacyDbPath);
    try {
      final rows = legacyDb.select('''
        SELECT
          id,
          title,
          subtitle,
          cover,
          time,
          type,
          ep,
          page,
          readEpisode,
          max_page,
          chapter_group
        FROM history
        ORDER BY time ASC;
        ''');

      var imported = 0;
      var skippedMissingComic = 0;

      for (final row in rows) {
        final legacy = _LegacyHistoryRow.fromRow(row);
        final comicId = _canonicalComicIdForLegacyHistory(legacy);
        final snapshot = await store.loadComicSnapshot(comicId);
        if (snapshot == null) {
          skippedMissingComic += 1;
          continue;
        }

        await store.upsertHistoryEvent(
          HistoryEventRecord(
            id: 'history:${legacy.typeValue}:${legacy.legacyId}',
            comicId: comicId,
            sourceTypeValue: legacy.typeValue,
            sourceKey: sourceKeyFromTypeValue(legacy.typeValue),
            title: legacy.title,
            subtitle: legacy.subtitle,
            cover: legacy.cover,
            eventTime: _isoTimestamp(legacy.eventTime),
            chapterIndex: legacy.ep,
            pageIndex: legacy.page,
            chapterGroup: legacy.chapterGroup,
            readEpisode: legacy.readEpisode,
            maxPage: legacy.maxPage,
          ),
        );
        imported += 1;
      }

      return LegacyHistoryMigrationReport(
        sourceDbPath: legacyDbPath,
        targetDbPath: store.dbPath,
        imported: imported,
        skippedMissingComic: skippedMissingComic,
      );
    } finally {
      legacyDb.dispose();
    }
  }
}

class _LegacyHistoryRow {
  const _LegacyHistoryRow({
    required this.legacyId,
    required this.title,
    required this.subtitle,
    required this.cover,
    required this.eventTime,
    required this.typeValue,
    required this.ep,
    required this.page,
    required this.readEpisode,
    this.maxPage,
    this.chapterGroup,
  });

  factory _LegacyHistoryRow.fromRow(sqlite.Row row) {
    return _LegacyHistoryRow(
      legacyId: row['id'] as String,
      title: row['title'] as String? ?? '',
      subtitle: row['subtitle'] as String? ?? '',
      cover: row['cover'] as String? ?? '',
      eventTime: DateTime.fromMillisecondsSinceEpoch(row['time'] as int? ?? 0),
      typeValue: row['type'] as int? ?? 0,
      ep: row['ep'] as int? ?? 0,
      page: row['page'] as int? ?? 0,
      readEpisode: row['readEpisode'] as String? ?? '',
      maxPage: row['max_page'] as int?,
      chapterGroup: row['chapter_group'] as int?,
    );
  }

  final String legacyId;
  final String title;
  final String subtitle;
  final String cover;
  final DateTime eventTime;
  final int typeValue;
  final int ep;
  final int page;
  final String readEpisode;
  final int? maxPage;
  final int? chapterGroup;
}

String _canonicalComicIdForLegacyHistory(_LegacyHistoryRow legacy) {
  if (legacy.typeValue == 0) {
    return 'legacy_local:${legacy.typeValue}:${legacy.legacyId}';
  }
  return 'legacy_source:${legacy.typeValue}:${legacy.legacyId}';
}

String _isoTimestamp(DateTime value) {
  return value.toUtc().toIso8601String();
}
