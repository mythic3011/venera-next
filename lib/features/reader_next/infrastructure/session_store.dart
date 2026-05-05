import 'dart:convert';

import 'package:venera/features/reader_next/runtime/models.dart';
import 'package:venera/features/reader_next/runtime/session.dart';
import 'package:venera/foundation/db/unified_comics_store.dart';

class DriftReaderSessionStore implements ReaderSessionStore {
  DriftReaderSessionStore({
    required UnifiedComicsStore store,
    this.sessionIdPrefix = 'reader-next-session',
    this.tabIdPrefix = 'reader-next-tab',
  }) : _store = store;

  final UnifiedComicsStore _store;
  final String sessionIdPrefix;
  final String tabIdPrefix;

  @override
  Future<ReaderResumeSession?> load({required String canonicalComicId}) async {
    final session = await _store.loadReaderSessionByComic(canonicalComicId);
    if (session == null) {
      return null;
    }
    final tabs = await _store.loadReaderTabsForSession(session.id);
    if (tabs.isEmpty) {
      return null;
    }
    final tab = session.activeTabId == null
        ? tabs.first
        : tabs.firstWhere(
            (candidate) => candidate.id == session.activeTabId,
            orElse: () => tabs.first,
          );
    final sourceRef = _decodeSourceRef(tab.sourceRefJson);
    return ReaderResumeSession(
      canonicalComicId: tab.comicId,
      sourceRef: sourceRef,
      chapterRefId: tab.chapterId,
      page: tab.pageIndex,
      pageOrderId: tab.pageOrderId,
    );
  }

  @override
  Future<void> save(ReaderResumeSession session) async {
    session.validate();
    final canonicalComicId = session.canonicalComicId;
    final sessionId = '$sessionIdPrefix:$canonicalComicId';
    final tabId = '$tabIdPrefix:$canonicalComicId';
    await _store.upsertComic(
      ComicRecord(
        id: canonicalComicId,
        title: canonicalComicId,
        normalizedTitle: canonicalComicId.toLowerCase(),
      ),
    );
    await _store.upsertReaderSession(
      ReaderSessionRecord(id: sessionId, comicId: canonicalComicId),
    );
    await _store.upsertReaderTab(
      ReaderTabRecord(
        id: tabId,
        sessionId: sessionId,
        comicId: canonicalComicId,
        chapterId: session.chapterRefId,
        pageIndex: session.page,
        sourceRefJson: _encodeSourceRef(session.sourceRef),
        pageOrderId: session.pageOrderId,
      ),
    );
    await _store.upsertReaderSession(
      ReaderSessionRecord(
        id: sessionId,
        comicId: canonicalComicId,
        activeTabId: tabId,
      ),
    );
  }

  String _encodeSourceRef(SourceRef sourceRef) {
    return jsonEncode({
      'type': sourceRef.type.name,
      'sourceKey': sourceRef.sourceKey,
      'upstreamComicRefId': sourceRef.upstreamComicRefId,
      'chapterRefId': sourceRef.chapterRefId,
    });
  }

  SourceRef _decodeSourceRef(String sourceRefJson) {
    final decoded = jsonDecode(sourceRefJson);
    if (decoded is! Map<String, dynamic>) {
      throw ReaderRuntimeException(
        'SESSION_INVALID',
        'sourceRefJson is malformed',
      );
    }
    final sourceKey = decoded['sourceKey']?.toString() ?? '';
    final upstreamComicRefId = decoded['upstreamComicRefId']?.toString() ?? '';
    final chapterRefId = decoded['chapterRefId']?.toString();
    final typeValue = decoded['type']?.toString();
    if (typeValue == SourceRefType.local.name) {
      return SourceRef.local(
        sourceKey: sourceKey,
        comicRefId: upstreamComicRefId,
        chapterRefId: chapterRefId,
      );
    }
    return SourceRef.remote(
      sourceKey: sourceKey,
      upstreamComicRefId: upstreamComicRefId,
      chapterRefId: chapterRefId,
    );
  }
}
