import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:venera/foundation/diagnostics/diagnostics.dart';
import 'package:venera/foundation/local/local_library_reconciler.dart';
import 'package:venera/foundation/repositories/local_library_repository.dart';

void main() {
  setUp(() {
    AppDiagnostics.configureSinksForTesting(const []);
  });

  tearDown(() {
    AppDiagnostics.resetForTesting();
  });

  test(
    'browse reconcile hides missing payload and keeps available comic',
    () async {
      final reconciler = const LocalLibraryReconciler();
      final tempRoot = await Directory.systemTemp.createTemp(
        'local-reconcile-ok-',
      );
      addTearDown(() => tempRoot.delete(recursive: true));
      final okDirectory = Directory('${tempRoot.path}/ok')..createSync();
      File('${okDirectory.path}/1.jpg').writeAsBytesSync(<int>[0]);

      final result = await reconciler.reconcileBrowseVisibility(
        items: const [
          LocalLibraryReconcileItem(
            comicId: 'missing',
            comicDirectoryName: 'm',
          ),
          LocalLibraryReconcileItem(comicId: 'ok', comicDirectoryName: 'ok'),
        ],
        loadPrimaryItem: (comicId) async {
          if (comicId == 'missing') {
            return const LocalLibraryPrimaryItem(
              id: 'lli-missing',
              storageType: 'user_imported',
              localRootPath: '/definitely/missing/path',
            );
          }
          return LocalLibraryPrimaryItem(
            id: 'lli-ok',
            storageType: 'user_imported',
            localRootPath: okDirectory.path,
          );
        },
      );

      expect(result.visibleComicIds, contains('ok'));
      expect(result.visibleComicIds, isNot(contains('missing')));
      expect(
        result.cleanupCandidateLocalLibraryItemIds,
        contains('lli-missing'),
      );
      final events = DevDiagnosticsApi.recent(channel: 'local.library');
      expect(
        events.any((event) => event.message == 'local.library.missingFiles'),
        isTrue,
      );
    },
  );

  test(
    'browse reconcile hides orphan row when canonical root exists but comic directory is missing',
    () async {
      final reconciler = const LocalLibraryReconciler();
      final tempRoot = await Directory.systemTemp.createTemp(
        'local-reconcile-orphan-',
      );
      addTearDown(() => tempRoot.delete(recursive: true));
      Directory('${tempRoot.path}/other-comic').createSync();

      final result = await reconciler.reconcileBrowseVisibility(
        items: const [
          LocalLibraryReconcileItem(
            comicId: 'orphan',
            comicDirectoryName: 'missing-dir',
          ),
        ],
        loadPrimaryItem: (_) async => LocalLibraryPrimaryItem(
          id: 'lli-orphan',
          storageType: 'user_imported',
          localRootPath: tempRoot.path,
        ),
        canonicalBrowseRootPath: tempRoot.path,
      );

      expect(result.visibleComicIds, isNot(contains('orphan')));
      expect(
        result.cleanupCandidateLocalLibraryItemIds,
        contains('lli-orphan'),
      );

      final event = DevDiagnosticsApi.recent(channel: 'local.library')
          .singleWhere((event) => event.message == 'local.library.missingFiles');
      expect(event.data['comicId'], 'orphan');
      expect(event.data['localItemId'], 'lli-orphan');
      expect(event.data['status'], 'missingDirectory');
      expect(event.data['action'], 'hide');
    },
  );

  test(
    'browse reconcile hides legacy-only items without canonical primary row',
    () async {
      final reconciler = const LocalLibraryReconciler();

      final result = await reconciler.reconcileBrowseVisibility(
        items: const [
          LocalLibraryReconcileItem(
            comicId: 'legacy-only',
            comicDirectoryName: 'legacy-dir',
          ),
        ],
        loadPrimaryItem: (_) async => null,
      );

      expect(result.visibleComicIds, isNot(contains('legacy-only')));
      expect(result.cleanupCandidateLocalLibraryItemIds, isEmpty);

      final event = DevDiagnosticsApi.recent(channel: 'local.library')
          .singleWhere(
            (event) => event.message == 'local.library.missingCanonicalItem',
          );
      expect(event.data['comicId'], 'legacy-only');
      expect(event.data['action'], 'hide');
    },
  );

  test('cleanup removes only eligible user_imported missing rows', () async {
    final reconciler = const LocalLibraryReconciler();
    final removed = <String>[];

    final count = await reconciler.cleanupMissingUserImportedItems(
      items: const [
        LocalLibraryReconcileItem(
          comicId: 'delete-me',
          comicDirectoryName: 'x',
        ),
        LocalLibraryReconcileItem(
          comicId: 'keep-unsafe',
          comicDirectoryName: '/abs/path',
        ),
        LocalLibraryReconcileItem(
          comicId: 'keep-available',
          comicDirectoryName: 'k',
        ),
      ],
      loadPrimaryItem: (comicId) async {
        if (comicId == 'delete-me') {
          return const LocalLibraryPrimaryItem(
            id: 'lli-delete',
            storageType: 'user_imported',
            localRootPath: '/missing/root/path',
          );
        }
        if (comicId == 'keep-unsafe') {
          return const LocalLibraryPrimaryItem(
            id: 'lli-unsafe',
            storageType: 'user_imported',
            localRootPath: '/root',
          );
        }
        return const LocalLibraryPrimaryItem(
          id: 'lli-available',
          storageType: 'downloaded',
          localRootPath: '/root',
        );
      },
      deleteLocalLibraryItem: (id) async {
        removed.add(id);
      },
    );

    expect(count, 1);
    expect(removed, ['lli-delete']);
  });
}
