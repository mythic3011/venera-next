import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:venera/foundation/appdata.dart';
import 'package:venera/foundation/appdata_authority_audit.dart';
import 'package:venera/foundation/comic_type.dart';
import 'package:venera/foundation/diagnostics/diagnostics.dart';
import 'package:venera/foundation/history.dart';
import 'package:venera/foundation/local.dart';
import 'package:venera/pages/favorites/favorites_page.dart';
import 'package:venera/pages/local_comics_page.dart';
import 'package:venera/foundation/reader/resume_target_store.dart';
import 'package:venera/foundation/source_ref.dart';

void main() {
  const trackerAuditKeys = <(
    String key,
    AppdataAuditStorage storage,
    AppdataAuditClassification classification
  )>[
    (
      'reader_use_source_ref_resolver',
      AppdataAuditStorage.settings,
      AppdataAuditClassification.featureFlag,
    ),
    (
      'reader_use_resume_source_ref_snapshot',
      AppdataAuditStorage.settings,
      AppdataAuditClassification.unknownNeedsOwner,
    ),
    (
      'reading_resume_targets_v1',
      AppdataAuditStorage.implicitData,
      AppdataAuditClassification.legacyBridge,
    ),
    (
      'comicSourceListUrl',
      AppdataAuditStorage.settings,
      AppdataAuditClassification.legacyBridge,
    ),
    (
      'favoriteFolder',
      AppdataAuditStorage.implicitData,
      AppdataAuditClassification.uiWorkflowState,
    ),
    (
      'local_sort',
      AppdataAuditStorage.implicitData,
      AppdataAuditClassification.uiPreference,
    ),
    (
      'local_favorites_read_filter',
      AppdataAuditStorage.implicitData,
      AppdataAuditClassification.uiPreference,
    ),
    (
      'local_favorites_update_page_num',
      AppdataAuditStorage.implicitData,
      AppdataAuditClassification.uiPreference,
    ),
    (
      'localDirectoryBookmark',
      AppdataAuditStorage.implicitData,
      AppdataAuditClassification.deviceIntegration,
    ),
    (
      'followUpdatesFolder',
      AppdataAuditStorage.settings,
      AppdataAuditClassification.uiWorkflowState,
    ),
    (
      'webdavAutoSync',
      AppdataAuditStorage.implicitData,
      AppdataAuditClassification.featureFlag,
    ),
    (
      'lastCheckUpdate',
      AppdataAuditStorage.implicitData,
      AppdataAuditClassification.runtimeCache,
    ),
  ];

  tearDown(() {
    AppDiagnostics.resetForTesting();
    DevDiagnosticsApi.debugEnabledOverride = null;
    appdata.settings['reader_use_source_ref_resolver'] = false;
    appdata.settings['reader_use_resume_source_ref_snapshot'] = null;
    appdata.implicitData.remove('reading_resume_targets_v1');
    HistoryManager.cache = null;
  });

  test('appdata audit marks resume source ref snapshot flag as unknown owner', () async {
    final entry = findAppdataAuditEntry(
      'reader_use_resume_source_ref_snapshot',
      storage: AppdataAuditStorage.settings,
    );

    expect(entry, isNotNull);
    expect(
      entry!.classification,
      AppdataAuditClassification.unknownNeedsOwner,
    );
  });

  test('appdata audit marks reading resume targets as legacy bridge', () async {
    final entry = findAppdataAuditEntry(
      'reading_resume_targets_v1',
      storage: AppdataAuditStorage.implicitData,
    );

    expect(entry, isNotNull);
    expect(entry!.classification, AppdataAuditClassification.legacyBridge);
  });

  test('history resume diagnostics report appdata implicitData as legacy bridge', () async {
    AppDiagnostics.configureSinksForTesting(const []);
    final store = ResumeTargetStore(<String, dynamic>{});

    store.readWithDiagnostic('comic-local-1', ComicType.local);

    final events = DevDiagnosticsApi.recent(channel: 'appdata.audit');
    final event = events.singleWhere(
      (candidate) =>
          candidate.message == 'appdata.authority.access' &&
          candidate.data['owner'] == 'ResumeTargetStore' &&
          candidate.data['key'] == 'reading_resume_targets_v1' &&
          candidate.data['access'] == 'read',
    );
    expect(event.data['storage'], 'implicitData');
    expect(event.data['classification'], 'legacy_bridge');
  });

  test('HistoryManager no longer reads reader_use_resume_source_ref_snapshot runtime flag', () async {
    AppDiagnostics.configureSinksForTesting(const []);
    appdata.settings['reader_use_resume_source_ref_snapshot'] = true;
    final store = ResumeTargetStore(appdata.implicitData);
    final sourceRef = SourceRef.fromLegacyLocal(
      localType: 'local',
      localComicId: 'comic-local-1',
      chapterId: null,
    );
    store.write(
      comicId: 'comic-local-1',
      type: ComicType.local,
      chapter: 1,
      group: null,
      page: 2,
      sourceRef: sourceRef,
    );

    final resolved = HistoryManager().findResumeSourceRef(
      'comic-local-1',
      ComicType.local,
    );

    expect(resolved?.id, sourceRef.id);
    final events = DevDiagnosticsApi.recent(channel: 'appdata.audit');
    expect(
      events.any((event) => event.data['key'] == 'reader_use_source_ref_resolver'),
      isFalse,
    );
    expect(
      events.any(
        (event) =>
            event.data['key'] == 'reader_use_resume_source_ref_snapshot' &&
            event.data['owner'] == 'HistoryManager',
      ),
      isFalse,
    );
    expect(
      events.any(
        (event) =>
            event.data['key'] == 'reading_resume_targets_v1' &&
            event.data['classification'] == 'legacy_bridge' &&
            event.data['owner'] == 'ResumeTargetStore' &&
            event.data['access'] == 'read',
      ),
      isTrue,
    );
  });

  test('every tracker audit key has a matching appdata authority audit entry', () async {
    for (final expected in trackerAuditKeys) {
      final entry = findAppdataAuditEntry(
        expected.$1,
        storage: expected.$2,
      );
      expect(entry, isNotNull, reason: 'missing audit entry for ${expected.$1}');
      expect(
        entry!.classification,
        expected.$3,
        reason: 'unexpected classification for ${expected.$1}',
      );
    }
    expect(appdataAuditEntries.length, trackerAuditKeys.length);
  });

  test('unknown keys fail explicit lookup as untracked', () async {
    expect(
      findAppdataAuditEntry(
        'reader_use_resume_source_ref_snapshot_typo',
        storage: AppdataAuditStorage.settings,
      ),
      isNull,
    );
    expect(
      findAppdataAuditEntry(
        'favoriteFolder',
        storage: AppdataAuditStorage.settings,
      ),
      isNull,
    );
  });

  test('ui and runtime audit keys keep non-authority classifications', () async {
    expect(
      findAppdataAuditEntry(
        'local_sort',
        storage: AppdataAuditStorage.implicitData,
      )!.classification,
      AppdataAuditClassification.uiPreference,
    );
    expect(
      findAppdataAuditEntry(
        'localDirectoryBookmark',
        storage: AppdataAuditStorage.implicitData,
      )!.classification,
      AppdataAuditClassification.deviceIntegration,
    );
    expect(
      findAppdataAuditEntry(
        'lastCheckUpdate',
        storage: AppdataAuditStorage.implicitData,
      )!.classification,
      AppdataAuditClassification.runtimeCache,
    );
    expect(
      findAppdataAuditEntry(
        'comicSourceListUrl',
        storage: AppdataAuditStorage.settings,
      )!.classification,
      AppdataAuditClassification.legacyBridge,
    );
  });

  test('resume source ref snapshot owner decision remains explicit', () async {
    final entry = findAppdataAuditEntry(
      'reader_use_resume_source_ref_snapshot',
      storage: AppdataAuditStorage.settings,
    );

    expect(entry, isNotNull);
    expect(
      entry!.ownerAction,
      contains('retire as runtime flag'),
    );
  });

  test('resume source ref snapshot flag owner decision is retire as runtime flag', () async {
    final entry = findAppdataAuditEntry(
      'reader_use_resume_source_ref_snapshot',
      storage: AppdataAuditStorage.settings,
    );

    expect(entry, isNotNull);
    expect(entry!.ownerAction, contains('retire as runtime flag'));
    expect(
      entry.ownerAction,
      contains('remove HistoryManager runtime dependency'),
    );
    expect(
      entry.ownerAction,
      contains('ReaderResumeService fallback injection'),
    );
  });

  test('resume source ref snapshot flag remains undeclared and has no default in owner decision slice', () async {
    final repoRoot = Directory.current.path;
    final settingsSchema = File(
      p.join(repoRoot, 'lib/pages/settings/settings_schema.dart'),
    ).readAsStringSync();
    final appdataDefaults = File(
      p.join(repoRoot, 'lib/foundation/appdata.dart'),
    ).readAsStringSync();

    expect(
      settingsSchema.contains('reader_use_resume_source_ref_snapshot'),
      isFalse,
    );
    expect(
      appdataDefaults.contains("'reader_use_resume_source_ref_snapshot'"),
      isFalse,
    );
  });

  test('comic source list url is classified as legacy source repository bridge', () async {
    final entry = findAppdataAuditEntry(
      'comicSourceListUrl',
      storage: AppdataAuditStorage.settings,
    );

    expect(entry, isNotNull);
    expect(entry!.classification, AppdataAuditClassification.legacyBridge);
    expect(
      entry.ownerAction,
      contains('repository registry is canonical authority'),
    );
  });

  test('reading resume targets are legacy fallback after canonical reader sessions', () async {
    final entry = findAppdataAuditEntry(
      'reading_resume_targets_v1',
      storage: AppdataAuditStorage.implicitData,
    );

    expect(entry, isNotNull);
    expect(entry!.classification, AppdataAuditClassification.legacyBridge);
    expect(entry.ownerAction, contains('canonical reader_sessions'));
  });

  test('reader resume legacy fallback remains owned by ReaderResumeService decision', () async {
    final entry = findAppdataAuditEntry(
      'reading_resume_targets_v1',
      storage: AppdataAuditStorage.implicitData,
    );

    expect(entry, isNotNull);
    expect(
      entry!.ownerAction,
      contains('explicit ReaderResumeService fallback injection'),
    );
  });

  test('follow updates folder remains ui workflow state and not authority', () async {
    final entry = findAppdataAuditEntry(
      'followUpdatesFolder',
      storage: AppdataAuditStorage.settings,
    );

    expect(entry, isNotNull);
    expect(entry!.classification, AppdataAuditClassification.uiWorkflowState);
    expect(entry.ownerAction, contains('not source/update authority'));
  });

  test('favorite folder reads emit appdata authority diagnostics', () async {
    AppDiagnostics.configureSinksForTesting(const []);
    appdata.implicitData['favoriteFolder'] = <String, dynamic>{
      'name': 'Folder A',
      'isNetwork': false,
    };

    final selection = readFavoritesFolderSelection();

    expect(selection?['name'], 'Folder A');
    final event = DevDiagnosticsApi.recent(channel: 'appdata.audit').singleWhere(
      (candidate) =>
          candidate.data['owner'] == 'FavoritesPage' &&
          candidate.data['key'] == 'favoriteFolder',
    );
    expect(event.data['storage'], 'implicitData');
    expect(event.data['classification'], 'ui_workflow_state');
    expect(event.data['access'], 'read');
  });

  test('local sort and favorites filters emit ui preference diagnostics', () async {
    AppDiagnostics.configureSinksForTesting(const []);
    appdata.implicitData['local_sort'] = 'time_desc';
    appdata.implicitData['local_favorites_read_filter'] = 'Unread';
    appdata.implicitData['local_favorites_update_page_num'] = 50;

    expect(readLocalSortPreference(), 'time_desc');
    expect(readLocalFavoritesReadFilterPreference('All'), 'Unread');
    expect(readLocalFavoritesUpdatePageNumPreference(9999999), 50);

    final events = DevDiagnosticsApi.recent(channel: 'appdata.audit');
    for (final key in const <String>[
      'local_sort',
      'local_favorites_read_filter',
      'local_favorites_update_page_num',
    ]) {
      final event = events.singleWhere((candidate) => candidate.data['key'] == key);
      expect(event.data['classification'], 'ui_preference');
      expect(event.data['access'], 'read');
    }
  });

  test('local directory bookmark reads emit device integration diagnostics', () async {
    AppDiagnostics.configureSinksForTesting(const []);
    appdata.implicitData['localDirectoryBookmark'] = 'bookmark-data';

    expect(readLocalDirectoryBookmark(), 'bookmark-data');

    final event = DevDiagnosticsApi.recent(channel: 'appdata.audit').singleWhere(
      (candidate) => candidate.data['key'] == 'localDirectoryBookmark',
    );
    expect(event.data['owner'], 'LocalManager');
    expect(event.data['classification'], 'device_integration');
    expect(event.data['access'], 'read');
  });
}
