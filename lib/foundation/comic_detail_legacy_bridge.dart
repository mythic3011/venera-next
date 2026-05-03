import 'package:venera/foundation/comic_detail/comic_detail.dart';
import 'package:venera/foundation/comic_type.dart';
import 'package:venera/foundation/app.dart';
import 'package:venera/foundation/db/local_comic_sync.dart';
import 'package:venera/foundation/db/unified_comics_store.dart';
import 'package:venera/foundation/download_queue_legacy_bridge.dart';
import 'package:venera/foundation/local_comics_legacy_bridge.dart';
import 'package:venera/foundation/local.dart';
import 'package:venera/network/download.dart';

class CanonicalLocalDetailRecord {
  const CanonicalLocalDetailRecord({
    required this.localComic,
    required this.detail,
  });

  final LocalComic localComic;
  final ComicDetailViewModel detail;
}

bool legacyIsDownloading(String comicId, ComicType type) {
  return legacyIsLocalComicDownloading(comicId, type);
}

bool legacyIsDownloaded(String comicId, ComicType type, int ep) {
  return legacyIsLocalComicDownloaded(comicId, type, ep);
}

LocalComic? legacyFindLocalComic(String comicId, ComicType type) {
  return legacyFindLocalComicByIdAndType(comicId, type);
}

void legacyAddDownloadTask(DownloadTask task) {
  legacyAddDownloadQueueTask(task);
}

Future<CanonicalLocalDetailRecord?> loadCanonicalLocalDetailRecord({
  required String comicId,
  UnifiedComicsStore? store,
}) async {
  final targetStore = store ?? App.unifiedComicsStore;
  final localComic = legacyFindLocalComic(comicId, ComicType.local);
  if (localComic == null) {
    return null;
  }
  await LocalComicCanonicalSyncService(
    store: targetStore,
  ).syncComic(localComic);
  final detail = await UnifiedLocalComicDetailRepository(
    store: targetStore,
  ).getComicDetail(comicId);
  if (detail == null) {
    return null;
  }
  return CanonicalLocalDetailRecord(localComic: localComic, detail: detail);
}
