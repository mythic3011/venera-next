import 'package:venera/features/sources/comic_source/comic_source.dart';
import 'package:venera/foundation/res.dart';
import 'package:venera/foundation/db/store_records.dart';
import 'package:venera/foundation/ports/comic_detail_store_port.dart';
import 'package:venera/foundation/ports/reader_session_store_port.dart';
import 'package:venera/features/reader/data/reader_session_repository.dart';

import 'package:venera/features/comic_detail/data/comic_detail_models.dart';

typedef ComicDetailLoader =
    Future<ComicDetailViewModel?> Function(String comicId);
typedef RemoteComicDetailsLoader =
    Future<Res<ComicDetails>> Function(String comicId);

abstract class ComicDetailRepository {
  Future<ComicDetailViewModel?> getComicDetail(String comicId);
}

class RemoteComicDetailRecord {
  const RemoteComicDetailRecord({
    required this.canonicalComicId,
    required this.detail,
  });

  final String canonicalComicId;
  final ComicDetails detail;
}

class StaticComicDetailRepository implements ComicDetailRepository {
  StaticComicDetailRepository(Map<String, ComicDetailViewModel> records)
    : records = Map.unmodifiable(records);

  final Map<String, ComicDetailViewModel> records;

  @override
  Future<ComicDetailViewModel?> getComicDetail(String comicId) async {
    return records[comicId];
  }
}

class CompositeComicDetailRepository implements ComicDetailRepository {
  CompositeComicDetailRepository({required List<ComicDetailLoader> loaders})
    : loaders = List.unmodifiable(loaders);

  final List<ComicDetailLoader> loaders;

  @override
  Future<ComicDetailViewModel?> getComicDetail(String comicId) async {
    for (final loader in loaders) {
      final detail = await loader(comicId);
      if (detail != null) {
        return detail;
      }
    }
    return null;
  }
}

class StubComicDetailRepository implements ComicDetailRepository {
  const StubComicDetailRepository({
    this.missingState = LibraryState.unavailable,
  });

  final LibraryState missingState;

  @override
  Future<ComicDetailViewModel?> getComicDetail(String comicId) async {
    return ComicDetailViewModel.scaffold(
      comicId: comicId,
      title: comicId,
      libraryState: missingState,
    );
  }
}

class UnifiedCanonicalComicDetailRepository implements ComicDetailRepository {
  const UnifiedCanonicalComicDetailRepository({
    required this.store,
    this.requireLocalLibraryItems = false,
    ReaderSessionRepository? readerSessions,
  }) : _readerSessions = readerSessions;

  final ComicDetailStorePort store;
  final bool requireLocalLibraryItems;
  ReaderSessionRepository get readerSessions {
    final configured = _readerSessions;
    if (configured != null) {
      return configured;
    }
    if (store is ReaderSessionStorePort) {
      return ReaderSessionRepository(store: store as ReaderSessionStorePort);
    }
    throw StateError(
      'ReaderSessionRepository must be provided when comic detail store does not implement ReaderSessionStorePort.',
    );
  }

  final ReaderSessionRepository? _readerSessions;

  @override
  Future<ComicDetailViewModel?> getComicDetail(String comicId) async {
    final snapshot = await store.loadComicSnapshot(comicId);
    if (snapshot == null) {
      return null;
    }
    if (requireLocalLibraryItems && snapshot.localLibraryItems.isEmpty) {
      return null;
    }

    final primaryLink = await store.loadPrimaryComicSourceLink(comicId);
    final primaryPlatform = primaryLink == null
        ? null
        : await store.loadSourcePlatformById(primaryLink.sourcePlatformId);
    final primarySource = _buildPrimarySource(primaryLink, primaryPlatform);
    final sourceTags = await _loadSourceTags(primaryLink, primaryPlatform);
    final userTags = (await store.loadUserTagsForComic(comicId))
        .map((tag) => ComicTagVm(id: tag.id, name: tag.name, color: tag.color))
        .toList(growable: false);

    final chapters = <ChapterVm>[];
    final latestHistory = await store.loadLatestHistoryEvent(comicId);
    final latestHistoryReadAt = _parseStoreDateTime(latestHistory?.eventTime);
    for (final chapter in snapshot.chapters) {
      chapters.add(
        ChapterVm(
          chapterId: chapter.id,
          title: chapter.title,
          chapterNo: chapter.chapterNo,
          pageCount: await store.countPagesForChapter(chapter.id),
          lastReadAt:
              _matchesHistoryChapter(
                chapterNo: chapter.chapterNo,
                historyChapterIndex: latestHistory?.chapterIndex,
              )
              ? latestHistoryReadAt
              : null,
        ),
      );
    }

    final summary = await store.loadPageOrderSummary(comicId);
    final readerTabs = await readerSessions.loadReaderTabs(comicId);
    final libraryState = _resolveLibraryState(
      localLibraryItems: snapshot.localLibraryItems,
      primarySource: primarySource,
    );
    return ComicDetailViewModel(
      comicId: snapshot.comic.id,
      title: snapshot.comic.title,
      coverLocalPath: snapshot.comic.coverLocalPath,
      libraryState: libraryState,
      primarySource: primarySource,
      userTags: userTags,
      sourceTags: sourceTags,
      chapters: chapters,
      readerTabs: readerTabs,
      pageOrderSummary: PageOrderSummaryVm(
        activeOrderId: summary.activeOrderId,
        activeOrderType: _mapPageOrderKind(summary.activeOrderType),
        totalOrders: summary.totalOrders,
        totalPageCount: summary.totalPageCount,
        visiblePageCount: summary.visiblePageCount,
      ),
      updatedAt: _parseStoreDateTime(snapshot.comic.updatedAt),
      availableActions: ComicDetailActions(
        canContinueReading: readerTabs.isNotEmpty || latestHistory != null,
        canStartReading: true,
        canOpenInNewTab: true,
        canFavorite: true,
        canManageUserTags: true,
        canViewSource: primarySource?.comicUrl != null,
        canManagePageOrder: true,
        canSearchRelatedRemote: true,
        canLinkRemoteSource: true,
      ),
    );
  }

  ComicSourceCitation? _buildPrimarySource(
    ComicSourceLinkRecord? link,
    SourcePlatformRecord? platform,
  ) {
    if (link == null || platform == null) {
      return null;
    }
    return ComicSourceCitation(
      platform: _mapPlatform(platform),
      relationType: link.linkStatus,
      comicUrl: link.sourceUrl,
      sourceTitle: link.sourceTitle,
      downloadedAt: _parseStoreDateTime(link.downloadedAt),
      lastVerifiedAt: _parseStoreDateTime(link.lastVerifiedAt),
    );
  }

  Future<List<SourceTagVm>> _loadSourceTags(
    ComicSourceLinkRecord? link,
    SourcePlatformRecord? platform,
  ) async {
    if (link == null || platform == null) {
      return const <SourceTagVm>[];
    }
    final platformRef = _mapPlatform(platform);
    final tags = await store.loadSourceTagsForComicSourceLink(link.id);
    return tags
        .map(
          (tag) => SourceTagVm(
            id: tag.id,
            name: tag.displayName,
            namespace: tag.namespace,
            platform: platformRef,
          ),
        )
        .toList(growable: false);
  }
}

class CanonicalRemoteComicDetailRepository {
  const CanonicalRemoteComicDetailRepository({required this.store});

  final ComicDetailStorePort store;

  Future<Res<RemoteComicDetailRecord>> getRemoteComicDetail({
    required String comicId,
    required RemoteComicDetailsLoader loadComicInfo,
  }) async {
    final remoteRes = await loadComicInfo(comicId);
    if (!remoteRes.success) {
      return Res.fromErrorRes(remoteRes, subData: remoteRes.subData);
    }
    final remoteDetail = remoteRes.data;
    final canonicalComicId = await store.syncRemoteComic(remoteDetail);
    final canonicalDetail = await UnifiedCanonicalComicDetailRepository(
      store: store,
    ).getComicDetail(canonicalComicId);
    return Res(
      RemoteComicDetailRecord(
        canonicalComicId: canonicalComicId,
        detail: canonicalDetail == null
            ? remoteDetail
            : _overlayCanonicalMetadata(
                remoteDetail: remoteDetail,
                canonicalDetail: canonicalDetail,
              ),
      ),
      subData: remoteRes.subData,
    );
  }
}

class UnifiedLocalComicDetailRepository
    extends UnifiedCanonicalComicDetailRepository {
  const UnifiedLocalComicDetailRepository({required super.store})
    : super(requireLocalLibraryItems: true);
}

LibraryState _resolveLibraryState({
  required List<LocalLibraryItemRecord> localLibraryItems,
  required ComicSourceCitation? primarySource,
}) {
  if (localLibraryItems.any((item) => item.storageType == 'downloaded')) {
    return LibraryState.downloaded;
  }
  if (localLibraryItems.isNotEmpty) {
    if (primarySource != null) {
      return LibraryState.localWithRemoteSource;
    }
    return LibraryState.localOnly;
  }
  if (primarySource != null) {
    return LibraryState.remoteOnly;
  }
  return LibraryState.unavailable;
}

SourcePlatformRef _mapPlatform(SourcePlatformRecord platform) {
  return SourcePlatformRef(
    platformId: platform.id,
    canonicalKey: platform.canonicalKey,
    displayName: platform.displayName,
    kind: _mapPlatformKind(platform.kind),
    matchedAlias: platform.canonicalKey,
    matchedAliasType: SourceAliasType.canonical,
  );
}

SourcePlatformKind _mapPlatformKind(String kind) {
  switch (kind) {
    case 'local':
      return SourcePlatformKind.local;
    case 'remote':
      return SourcePlatformKind.remote;
    case 'virtual':
    default:
      return SourcePlatformKind.virtual;
  }
}

bool _matchesHistoryChapter({
  required double? chapterNo,
  required int? historyChapterIndex,
}) {
  if (chapterNo == null || historyChapterIndex == null) {
    return false;
  }
  return chapterNo == historyChapterIndex.toDouble();
}

DateTime? _parseStoreDateTime(String? value) {
  if (value == null) {
    return null;
  }
  return DateTime.tryParse(value)?.toLocal();
}

PageOrderKind? _mapPageOrderKind(String? orderType) {
  switch (orderType) {
    case 'source_default':
      return PageOrderKind.sourceDefault;
    case 'user_custom':
      return PageOrderKind.userCustom;
    case 'imported_folder':
      return PageOrderKind.importedFolder;
    case 'temporary_session':
      return PageOrderKind.temporarySession;
    default:
      return null;
  }
}

ComicDetails _overlayCanonicalMetadata({
  required ComicDetails remoteDetail,
  required ComicDetailViewModel canonicalDetail,
}) {
  final tags = <String, List<String>>{};
  for (final tag in canonicalDetail.sourceTags) {
    final key = tag.namespace.isEmpty ? 'Source Tags' : tag.namespace;
    tags.putIfAbsent(key, () => <String>[]).add(tag.name);
  }
  if (canonicalDetail.userTags.isNotEmpty) {
    tags['User Tags'] = canonicalDetail.userTags
        .map((tag) => tag.name)
        .toList(growable: false);
  }
  if (tags.isEmpty) {
    return remoteDetail;
  }
  return remoteDetail.copyWith(
    description:
        canonicalDetail.primarySource?.sourceTitle ?? remoteDetail.description,
    url: canonicalDetail.primarySource?.comicUrl ?? remoteDetail.url,
    tags: tags,
  );
}
