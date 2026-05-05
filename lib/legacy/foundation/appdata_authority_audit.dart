import 'package:venera/foundation/diagnostics/diagnostics.dart';

enum AppdataAuditStorage { settings, implicitData }

enum AppdataAuditClassification {
  uiPreference('ui_preference'),
  featureFlag('feature_flag'),
  migratedCanonicalAuthority('migrated_canonical_authority'),
  legacyBridge('legacy_bridge'),
  unknownNeedsOwner('unknown_needs_owner'),
  runtimeCache('runtime_cache'),
  deviceIntegration('device_integration'),
  uiWorkflowState('ui_workflow_state');

  const AppdataAuditClassification(this.label);

  final String label;
}

class AppdataAuditEntry {
  const AppdataAuditEntry({
    required this.key,
    required this.storage,
    required this.classification,
    required this.currentReaderWriter,
    required this.ownerAction,
  });

  final String key;
  final AppdataAuditStorage storage;
  final AppdataAuditClassification classification;
  final String currentReaderWriter;
  final String ownerAction;
}

const appdataAuditEntries = <AppdataAuditEntry>[
  AppdataAuditEntry(
    key: 'reader_use_source_ref_resolver',
    storage: AppdataAuditStorage.settings,
    classification: AppdataAuditClassification.featureFlag,
    currentReaderWriter: 'HistoryManager, reader resume path, settings schema',
    ownerAction: 'keep as typed setting; not authority by itself',
  ),
  AppdataAuditEntry(
    key: 'reader_use_resume_source_ref_snapshot',
    storage: AppdataAuditStorage.settings,
    classification: AppdataAuditClassification.unknownNeedsOwner,
    currentReaderWriter: 'no runtime reader; retired migration flag residue',
    ownerAction:
        'owner decision: retire as runtime flag; remove HistoryManager runtime dependency in a migration slice and keep ReaderResumeService fallback injection as the explicit compatibility path; do not add default or SettingKey',
  ),
  AppdataAuditEntry(
    key: 'reading_resume_targets_v1',
    storage: AppdataAuditStorage.implicitData,
    classification: AppdataAuditClassification.legacyBridge,
    currentReaderWriter: 'ResumeTargetStore(appdata.implicitData)',
    ownerAction:
        'legacy fallback bridge after canonical reader_sessions; keep compatibility-only and candidate read-only through explicit ReaderResumeService fallback injection',
  ),
  AppdataAuditEntry(
    key: 'comicSourceListUrl',
    storage: AppdataAuditStorage.settings,
    classification: AppdataAuditClassification.legacyBridge,
    currentReaderWriter:
        'source init + repository seeding + legacy UI entrypoints',
    ownerAction:
        'legacy bridge for repository registry seeding/import fallback; repository registry is canonical authority',
  ),
  AppdataAuditEntry(
    key: 'favoriteFolder',
    storage: AppdataAuditStorage.implicitData,
    classification: AppdataAuditClassification.uiWorkflowState,
    currentReaderWriter: 'favorites page selection state',
    ownerAction: 'retain as view state; not favorites authority',
  ),
  AppdataAuditEntry(
    key: 'local_sort',
    storage: AppdataAuditStorage.implicitData,
    classification: AppdataAuditClassification.uiPreference,
    currentReaderWriter: 'local comics page sort selection',
    ownerAction: 'retain as view preference',
  ),
  AppdataAuditEntry(
    key: 'local_favorites_read_filter',
    storage: AppdataAuditStorage.implicitData,
    classification: AppdataAuditClassification.uiPreference,
    currentReaderWriter: 'local favorites page filter selection',
    ownerAction: 'retain as view preference',
  ),
  AppdataAuditEntry(
    key: 'local_favorites_update_page_num',
    storage: AppdataAuditStorage.implicitData,
    classification: AppdataAuditClassification.uiPreference,
    currentReaderWriter: 'local favorites page pagination/filter state',
    ownerAction: 'retain as view preference',
  ),
  AppdataAuditEntry(
    key: 'localDirectoryBookmark',
    storage: AppdataAuditStorage.implicitData,
    classification: AppdataAuditClassification.deviceIntegration,
    currentReaderWriter: 'iOS local directory restore path',
    ownerAction: 'retain as device-local integration data',
  ),
  AppdataAuditEntry(
    key: 'followUpdatesFolder',
    storage: AppdataAuditStorage.settings,
    classification: AppdataAuditClassification.uiWorkflowState,
    currentReaderWriter: 'follow-updates page + favorites manager',
    ownerAction: 'retain as UI workflow state; not source/update authority',
  ),
  AppdataAuditEntry(
    key: 'webdavAutoSync',
    storage: AppdataAuditStorage.implicitData,
    classification: AppdataAuditClassification.featureFlag,
    currentReaderWriter: 'init/bootstrap + settings gateway',
    ownerAction: 'retain as device/runtime preference',
  ),
  AppdataAuditEntry(
    key: 'lastCheckUpdate',
    storage: AppdataAuditStorage.implicitData,
    classification: AppdataAuditClassification.runtimeCache,
    currentReaderWriter: 'startup update check throttle',
    ownerAction: 'retain as cache-like throttle state',
  ),
];

AppdataAuditEntry? findAppdataAuditEntry(
  String key, {
  AppdataAuditStorage? storage,
}) {
  for (final entry in appdataAuditEntries) {
    if (entry.key == key && (storage == null || entry.storage == storage)) {
      return entry;
    }
  }
  return null;
}

void recordAppdataAuthorityDiagnostic({
  required String channel,
  required String event,
  required String key,
  required AppdataAuditStorage storage,
  required String access,
  Map<String, Object?> data = const <String, Object?>{},
}) {
  final entry = findAppdataAuditEntry(key, storage: storage);
  AppDiagnostics.trace(
    channel,
    event,
    data: <String, Object?>{
      'key': key,
      'storage': storage.name,
      'access': access,
      'classification': entry?.classification.label ?? 'uncataloged',
      'currentReaderWriter': entry?.currentReaderWriter,
      'ownerAction': entry?.ownerAction,
      ...data,
    },
  );
}
