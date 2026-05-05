import 'dart:convert';

import 'package:venera/features/comic_detail/data/comic_detail_models.dart';
import 'package:venera/foundation/db/store_records.dart'
    show ReaderSessionRecord, ReaderTabRecord;
import 'package:venera/foundation/ports/reader_session_store_port.dart';
import 'package:venera/foundation/sources/source_ref.dart';

class ReaderSessionRepository {
  const ReaderSessionRepository({required this.store});

  final ReaderSessionStorePort store;

  static String sessionIdForComic(String comicId) {
    return 'reader-session:${Uri.encodeComponent(comicId)}';
  }

  static String defaultTabIdForSourceRef(SourceRef sourceRef) {
    return sourceRef.id;
  }

  Future<List<ReaderTabVm>> loadReaderTabs(String comicId) async {
    final session = await store.loadReaderSessionByComic(comicId);
    if (session == null) {
      return const <ReaderTabVm>[];
    }
    final tabs = await store.loadReaderTabsForSession(session.id);
    return tabs
        .map((tab) => _mapTab(tab, activeTabId: session.activeTabId))
        .toList(growable: false);
  }

  Future<ReaderTabVm?> loadActiveReaderTab(String comicId) async {
    final tabs = await loadReaderTabs(comicId);
    for (final tab in tabs) {
      if (tab.isActive) {
        return tab;
      }
    }
    return tabs.isEmpty ? null : tabs.first;
  }

  Future<void> upsertCurrentLocation({
    required String comicId,
    required String chapterId,
    required int pageIndex,
    required SourceRef sourceRef,
    String? pageOrderId,
    String? tabId,
    bool makeActive = true,
  }) async {
    final sessionId = sessionIdForComic(comicId);
    final resolvedTabId = tabId ?? defaultTabIdForSourceRef(sourceRef);
    await store.upsertReaderSession(
      ReaderSessionRecord(id: sessionId, comicId: comicId),
    );
    await store.upsertReaderTab(
      ReaderTabRecord(
        id: resolvedTabId,
        sessionId: sessionId,
        comicId: comicId,
        chapterId: chapterId,
        pageIndex: pageIndex,
        sourceRefJson: jsonEncode(sourceRef.toJson()),
        pageOrderId: pageOrderId,
      ),
    );
    if (makeActive) {
      await store.upsertReaderSession(
        ReaderSessionRecord(
          id: sessionId,
          comicId: comicId,
          activeTabId: resolvedTabId,
        ),
      );
    }
  }

  Future<void> markActiveTab({
    required String comicId,
    required String tabId,
  }) async {
    final session = await store.loadReaderSessionByComic(comicId);
    if (session == null) {
      throw StateError('No reader session exists for comic $comicId.');
    }
    await store.setReaderSessionActiveTab(
      sessionId: session.id,
      activeTabId: tabId,
    );
  }

  Future<void> deleteSession(String comicId) async {
    final session = await store.loadReaderSessionByComic(comicId);
    if (session == null) {
      return;
    }
    await store.deleteReaderSession(session.id);
  }

  ReaderTabVm _mapTab(ReaderTabRecord tab, {required String? activeTabId}) {
    final sourceRef = SourceRef.fromJson(
      Map<String, dynamic>.from(jsonDecode(tab.sourceRefJson) as Map),
    );
    return ReaderTabVm(
      tabId: tab.id,
      currentChapterId: tab.chapterId,
      currentPageIndex: tab.pageIndex,
      sourceRef: sourceRef,
      loadMode: sourceRef.type == SourceRefType.local
          ? ReaderTabLoadMode.localLibrary
          : ReaderTabLoadMode.remoteSource,
      pageOrderId: tab.pageOrderId,
      isActive: tab.id == activeTabId,
      updatedAt: DateTime.tryParse(tab.updatedAt ?? ''),
    );
  }
}
