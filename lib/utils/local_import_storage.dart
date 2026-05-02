import 'dart:async';

import 'package:venera/foundation/app.dart';
import 'package:venera/foundation/db/local_comic_sync.dart';
import 'package:venera/foundation/diagnostics/diagnostics.dart';
import 'package:venera/foundation/local.dart';
import 'package:venera/foundation/local_comics_legacy_bridge.dart';
import 'package:venera/foundation/local_storage_legacy_bridge.dart';

abstract class LocalImportStoragePort {
  Future<void> assertStorageReadyForImport(String comicTitle);
  Future<bool> hasDuplicateTitle(String title);
  Future<String> requireRootPath();
  Future<LocalComic> registerImportedComic(LocalComic comic);
}

class CanonicalLocalImportStorage implements LocalImportStoragePort {
  const CanonicalLocalImportStorage({
    this.loadBrowseRecords,
    this.tryReadRootPath,
    this.findDefaultRootPath,
    this.legacyLookup,
    this.legacyRegister,
    this.syncComic,
    this.idSeed,
  });

  final Future<List<dynamic>> Function()? loadBrowseRecords;
  final String? Function()? tryReadRootPath;
  final Future<String> Function()? findDefaultRootPath;
  final LegacyLocalComicLookupResult Function(String title)? legacyLookup;
  final Future<void> Function(LocalComic comic, String id)? legacyRegister;
  final Future<void> Function(LocalComic comic)? syncComic;
  final String Function()? idSeed;

  Future<List<dynamic>> _loadCanonicalBrowseRecords(String comicTitle) async {
    AppDiagnostics.trace(
      'import.local',
      'import.local.storageRoute',
      data: {
        'comicTitle': comicTitle,
        'authority': 'canonical_local_library',
        'storage': 'canonical_db',
      },
    );
    try {
      final rows =
          await (loadBrowseRecords ??
              () => App.repositories.localLibrary.store
                  .loadLocalLibraryBrowseRecords())();
      AppDiagnostics.trace(
        'import.local',
        'import.local.canonicalReady',
        data: {
          'comicTitle': comicTitle,
          'storage': 'canonical_db',
          'browseRecordCount': rows.length,
        },
      );
      return rows;
    } catch (error) {
      throw Exception(
        'Canonical local library unavailable (fail closed): '
        'CANONICAL_UNAVAILABLE',
      );
    }
  }

  void _probeLegacyAvailability(String comicTitle) {
    final result = (legacyLookup ?? legacyLookupLocalComicByName).call(
      comicTitle,
    );
    if (result is LegacyLocalComicLookupUnavailable) {
      AppDiagnostics.warn(
        'import.local',
        'import.local.legacyBlocked',
        data: {
          'comicTitle': comicTitle,
          'code': result.code,
          'authority': 'legacy_local_db',
        },
      );
    }
  }

  String _normalizeTitle(String title) => title.trim().toLowerCase();

  @override
  Future<void> assertStorageReadyForImport(String comicTitle) async {
    _probeLegacyAvailability(comicTitle);
    await _loadCanonicalBrowseRecords(comicTitle);
  }

  @override
  Future<bool> hasDuplicateTitle(String title) async {
    final normalizedTitle = _normalizeTitle(title);
    final rows = await _loadCanonicalBrowseRecords(title);
    for (final row in rows) {
      final dynamicRecord = row;
      final recordTitle = dynamicRecord.title?.toString() ?? '';
      final recordNormalized = dynamicRecord.normalizedTitle?.toString() ?? '';
      if (_normalizeTitle(recordTitle) == normalizedTitle ||
          _normalizeTitle(recordNormalized) == normalizedTitle) {
        return true;
      }
    }
    return false;
  }

  @override
  Future<String> requireRootPath() async {
    final configuredPath = (tryReadRootPath ?? tryReadLocalComicsStoragePath)
        .call();
    if (configuredPath != null && configuredPath.trim().isNotEmpty) {
      return configuredPath.trim();
    }
    try {
      final fallbackPath =
          await (findDefaultRootPath ??
              () => LocalManager().findDefaultPath())();
      if (fallbackPath.trim().isEmpty) {
        throw Exception('empty path');
      }
      return fallbackPath.trim();
    } catch (_) {
      throw Exception(
        'Canonical local storage unavailable (fail closed): '
        'CANONICAL_ROOT_UNAVAILABLE',
      );
    }
  }

  Future<String> _allocateComicId() async {
    final baseSeed =
        (idSeed ?? () => DateTime.now().microsecondsSinceEpoch.toString())();
    final store = App.unifiedComicsStore;
    var suffix = 0;
    while (true) {
      final candidate = suffix == 0 ? baseSeed : '$baseSeed-$suffix';
      final existing = await store.loadComicSnapshot(candidate);
      if (existing == null) {
        return candidate;
      }
      suffix++;
    }
  }

  @override
  Future<LocalComic> registerImportedComic(LocalComic comic) async {
    final id = await _allocateComicId();
    final registeredComic = LocalComic(
      id: id,
      title: comic.title,
      subtitle: comic.subtitle,
      tags: comic.tags,
      directory: comic.directory,
      chapters: comic.chapters,
      cover: comic.cover,
      comicType: comic.comicType,
      downloadedChapters: comic.downloadedChapters,
      createdAt: comic.createdAt,
    );
    await (syncComic ??
        (LocalComic comic) => LocalComicCanonicalSyncService(
          store: App.unifiedComicsStore,
        ).syncComic(comic))(registeredComic);
    try {
      await (legacyRegister ??
          (LocalComic comic, String id) => Future<void>.sync(
            () => legacyRegisterLocalComic(comic, id),
          ))(registeredComic, id);
    } catch (error) {
      final text = error.toString();
      if (text.contains('LateInitializationError') ||
          text.contains('late initialization')) {
        AppDiagnostics.warn(
          'import.local',
          'import.local.legacyBlocked',
          data: {
            'comicTitle': registeredComic.title,
            'code': 'LEGACY_UNAVAILABLE',
            'authority': 'legacy_local_db',
            'stage': 'register_mirror',
          },
        );
      } else {
        rethrow;
      }
    }
    return registeredComic;
  }
}
