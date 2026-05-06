import 'dart:async';

import 'package:venera/foundation/comic_type.dart';
import 'package:venera/foundation/db/remote_comic_sync.dart';
import 'package:venera/foundation/diagnostics/diagnostics.dart';
import 'package:venera/foundation/history.dart';
import 'package:venera/foundation/reader/reader_diagnostics.dart';
import 'package:venera/foundation/reader/reader_open_target.dart';
import 'package:venera/foundation/reader/resume_target_store.dart';
import 'package:venera/features/reader/data/reader_session_repository.dart';
import 'package:venera/foundation/sources/source_ref.dart';

typedef LegacyResumeSnapshotLoader =
    FutureOr<ResumeSnapshotReadResult> Function(String comicId, ComicType type);

class ReaderLegacyResumeMigrationAdapter {
  const ReaderLegacyResumeMigrationAdapter({
    required this.readerSessions,
    required this.loadLegacySnapshot,
  });

  factory ReaderLegacyResumeMigrationAdapter.fromHistoryManager({
    required ReaderSessionRepository readerSessions,
    HistoryManager? historyManager,
  }) {
    final manager = historyManager ?? HistoryManager();
    return ReaderLegacyResumeMigrationAdapter(
      readerSessions: readerSessions,
      loadLegacySnapshot: manager.readResumeSnapshotWithDiagnostic,
    );
  }

  final ReaderSessionRepository readerSessions;
  final LegacyResumeSnapshotLoader loadLegacySnapshot;

  Future<ReaderOpenTarget?> loadAndMigratePreferredResumeTarget(
    String comicId,
    ComicType type,
  ) async {
    final canonicalComicId = type == ComicType.local
        ? comicId
        : canonicalRemoteComicId(sourceKey: type.sourceKey, comicId: comicId);
    final canonicalActiveTab = await readerSessions.loadActiveReaderTab(
      canonicalComicId,
    );
    if (canonicalActiveTab != null) {
      return ReaderOpenTarget(sourceRef: canonicalActiveTab.sourceRef);
    }

    final result = await loadLegacySnapshot(comicId, type);
    final snapshot = result.snapshot;
    if (snapshot == null) {
      ReaderDiagnostics.recordResumeLookupEvent(
        event: 'reader.session.load.legacy_migration_miss',
        comicId: canonicalComicId,
        sourceKey: type.sourceKey,
        loadMode: type == ComicType.local ? 'local' : 'remote',
        fallbackSource: 'reading_resume_targets_v1',
      );
      return null;
    }

    final sourceRef = snapshot.sourceRef;
    if (_isUnresolvedLocalReaderTarget(sourceRef)) {
      AppDiagnostics.warn(
        'reader.route',
        'reader.route.unresolved_target',
        data: <String, Object?>{
          'comicId': comicId,
          'sourceKey': sourceRef.sourceKey,
          'sourceRefId': sourceRef.id,
          'reason': 'missingLocalChapterId',
          'migrationSource': 'reading_resume_targets_v1',
        },
      );
      ReaderDiagnostics.recordResumeLookupEvent(
        event: 'reader.session.load.legacy_migration_blocked',
        comicId: canonicalComicId,
        sourceKey: sourceRef.sourceKey,
        loadMode: 'local',
        fallbackSource: 'reading_resume_targets_v1',
        chapterId: sourceRef.params['chapterId']?.toString(),
      );
      return null;
    }

    final chapterId = sourceRef.params['chapterId']?.toString();
    if (chapterId == null || chapterId.isEmpty) {
      ReaderDiagnostics.recordResumeLookupEvent(
        event: 'reader.session.load.legacy_migration_blocked',
        comicId: canonicalComicId,
        sourceKey: sourceRef.sourceKey,
        loadMode: sourceRef.type == SourceRefType.local ? 'local' : 'remote',
        fallbackSource: 'reading_resume_targets_v1',
      );
      return null;
    }

    await readerSessions.upsertCurrentLocation(
      comicId: canonicalComicId,
      chapterId: chapterId,
      pageIndex: snapshot.target.pageIndex,
      sourceRef: sourceRef,
    );

    final migratedActiveTab = await readerSessions.loadActiveReaderTab(
      canonicalComicId,
    );
    if (migratedActiveTab == null) {
      ReaderDiagnostics.recordResumeLookupEvent(
        event: 'reader.session.load.legacy_migration_miss',
        comicId: canonicalComicId,
        sourceKey: sourceRef.sourceKey,
        loadMode: sourceRef.type == SourceRefType.local ? 'local' : 'remote',
        fallbackSource: 'reading_resume_targets_v1',
        chapterId: sourceRef.params['chapterId']?.toString(),
      );
      return null;
    }
    final migratedTarget = ReaderOpenTarget(
      sourceRef: migratedActiveTab.sourceRef,
    );
    final migratedSourceRef = migratedTarget.sourceRef;
    ReaderDiagnostics.recordResumeLookupEvent(
      event: 'reader.session.load.legacy_migration_hit',
      comicId: canonicalComicId,
      sourceKey: migratedSourceRef.sourceKey,
      loadMode: migratedSourceRef.type == SourceRefType.local
          ? 'local'
          : 'remote',
      fallbackSource: 'reading_resume_targets_v1',
      chapterId: migratedSourceRef.params['chapterId']?.toString(),
      tabId: migratedActiveTab.tabId,
    );
    return migratedTarget;
  }
}

bool _isUnresolvedLocalReaderTarget(SourceRef sourceRef) {
  if (sourceRef.type != SourceRefType.local) {
    return false;
  }
  final chapterId = sourceRef.params['chapterId']?.toString();
  return chapterId == null || chapterId.isEmpty;
}
