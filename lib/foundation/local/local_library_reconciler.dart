import 'package:path/path.dart' as p;
import 'package:venera/foundation/diagnostics/diagnostics.dart';
import 'package:venera/foundation/local/local_library_file_probe.dart';
import 'package:venera/foundation/repositories/local_library_repository.dart';

class LocalLibraryReconcileItem {
  const LocalLibraryReconcileItem({
    required this.comicId,
    required this.comicDirectoryName,
  });

  final String comicId;
  final String comicDirectoryName;
}

class LocalLibraryBrowseReconcileResult {
  const LocalLibraryBrowseReconcileResult({
    required this.visibleComicIds,
    required this.cleanupCandidateLocalLibraryItemIds,
  });

  final Set<String> visibleComicIds;
  final Set<String> cleanupCandidateLocalLibraryItemIds;
}

class LocalLibraryReconciler {
  const LocalLibraryReconciler({
    this.fileProbe = const LocalLibraryFileProbe(),
  });

  final LocalLibraryFileProbe fileProbe;

  Future<LocalLibraryBrowseReconcileResult> reconcileBrowseVisibility({
    required List<LocalLibraryReconcileItem> items,
    required Future<LocalLibraryPrimaryItem?> Function(String comicId)
    loadPrimaryItem,
    String? canonicalBrowseRootPath,
  }) async {
    final visibleComicIds = <String>{};
    final cleanupCandidates = <String>{};

    for (final item in items) {
      final primaryItem = await loadPrimaryItem(item.comicId);
      if (primaryItem == null) {
        AppDiagnostics.info(
          'local.library',
          'local.library.missingCanonicalItem',
          data: <String, Object?>{
            'comicId': item.comicId,
            'comicDirectoryName': item.comicDirectoryName,
            'action': 'hide',
          },
        );
        continue;
      }

      final probeResult = canonicalBrowseRootPath == null
          ? fileProbe.probe(
              canonicalRootPath: p.dirname(primaryItem.localRootPath),
              comicDirectoryName: item.comicDirectoryName,
              preferredExpectedDirectory: primaryItem.localRootPath,
            )
          : fileProbe.probe(
              canonicalRootPath: canonicalBrowseRootPath,
              comicDirectoryName: item.comicDirectoryName,
            );

      if (probeResult.isAvailable) {
        visibleComicIds.add(item.comicId);
        continue;
      }

      if (probeResult.isCleanupCandidate) {
        cleanupCandidates.add(primaryItem.id);
      }

      AppDiagnostics.warn(
        'local.library',
        'local.library.missingFiles',
        data: <String, Object?>{
          'comicId': item.comicId,
          'localItemId': primaryItem.id,
          'status': probeResult.status.name,
          'expectedDirectory': probeResult.expectedDirectory,
          'action': 'hide',
        },
      );
    }

    return LocalLibraryBrowseReconcileResult(
      visibleComicIds: visibleComicIds,
      cleanupCandidateLocalLibraryItemIds: cleanupCandidates,
    );
  }

  Future<int> cleanupMissingUserImportedItems({
    required List<LocalLibraryReconcileItem> items,
    required Future<LocalLibraryPrimaryItem?> Function(String comicId)
    loadPrimaryItem,
    required Future<void> Function(String localLibraryItemId)
    deleteLocalLibraryItem,
  }) async {
    var removed = 0;
    for (final item in items) {
      final primaryItem = await loadPrimaryItem(item.comicId);
      if (primaryItem == null || primaryItem.storageType != 'user_imported') {
        continue;
      }
      final probeResult = fileProbe.probe(
        canonicalRootPath: primaryItem.localRootPath,
        comicDirectoryName: item.comicDirectoryName,
        preferredExpectedDirectory: primaryItem.localRootPath,
      );
      if (!probeResult.isCleanupCandidate) {
        continue;
      }
      if (probeResult.status == LocalLibraryFileStatus.unsafePath) {
        continue;
      }

      AppDiagnostics.warn(
        'local.library',
        'local.library.missingFiles',
        data: <String, Object?>{
          'comicId': item.comicId,
          'localItemId': primaryItem.id,
          'status': probeResult.status.name,
          'expectedDirectory': probeResult.expectedDirectory,
          'action': 'cleanup_candidate',
        },
      );

      await deleteLocalLibraryItem(primaryItem.id);
      removed++;

      AppDiagnostics.warn(
        'local.library',
        'local.library.missingFiles',
        data: <String, Object?>{
          'comicId': item.comicId,
          'localItemId': primaryItem.id,
          'status': probeResult.status.name,
          'expectedDirectory': probeResult.expectedDirectory,
          'action': 'removed',
        },
      );
    }
    return removed;
  }
}
