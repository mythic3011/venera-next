import 'package:flutter_test/flutter_test.dart';
import 'package:venera/foundation/comic_type.dart';
import 'package:venera/foundation/reader/resume_target_store.dart';
import 'package:venera/foundation/source_ref.dart';

void main() {
  test('resume_snapshot_roundtrip_preserves_local_source_ref', () {
    final implicitData = <String, dynamic>{};
    final store = ResumeTargetStore(implicitData);
    final localRef = SourceRef.fromLegacyLocal(
      localType: 'local',
      localComicId: 'comic-local-1',
      chapterId: null,
    );

    store.write(
      comicId: 'comic-local-1',
      type: ComicType.local,
      chapter: 1,
      group: null,
      page: 5,
      sourceRef: localRef,
    );

    final restored = store.read('comic-local-1', ComicType.local);
    expect(restored, isNotNull);
    expect(restored!.sourceRef.type, SourceRefType.local);
    expect(restored.sourceRef.sourceKey, 'local');
    expect(restored.sourceRef.id, localRef.id);
  });

  test('remote_write_does_not_hijack_existing_local_snapshot', () {
    final implicitData = <String, dynamic>{};
    final store = ResumeTargetStore(implicitData);
    final localRef = SourceRef.fromLegacyLocal(
      localType: 'local',
      localComicId: 'series-1',
      chapterId: 'ch-1',
    );
    final remoteRef = SourceRef.fromLegacyRemote(
      sourceKey: 'copymanga',
      comicId: 'series-1',
      chapterId: 'ch-1',
    );

    store.write(
      comicId: 'series-1',
      type: ComicType.local,
      chapter: 1,
      group: null,
      page: 3,
      sourceRef: localRef,
    );
    store.write(
      comicId: 'series-1',
      type: ComicType(999001),
      chapter: 1,
      group: null,
      page: 3,
      sourceRef: remoteRef,
    );

    final localSnapshot = store.read('series-1', ComicType.local);
    final remoteSnapshot = store.read('series-1', ComicType(999001));
    expect(localSnapshot, isNotNull);
    expect(remoteSnapshot, isNotNull);
    expect(localSnapshot!.sourceRef.type, SourceRefType.local);
    expect(remoteSnapshot!.sourceRef.type, SourceRefType.remote);
  });

  test('unsupported_version_returns_null_snapshot', () {
    final implicitData = <String, dynamic>{
      'reading_resume_targets_v1': {
        '0:series-1': {
          'version': 999,
          'target': {
            'seriesId': 'series-1',
            'chapterEntryId': '1',
            'sourceRefId': 'local:local:series-1:_',
            'sourceRefType': 'local',
            'sourceKey': 'local',
            'pageIndex': 1,
            'updatedAtMs': 1,
          },
          'sourceRef': {
            'id': 'local:local:series-1:_',
            'type': 'local',
            'sourceKey': 'local',
            'refId': 'series-1',
          },
        },
      },
    };
    final store = ResumeTargetStore(implicitData);
    final result = store.readWithDiagnostic('series-1', ComicType.local);
    expect(result.snapshot, isNull);
    expect(
      result.diagnostic,
      ResumeSnapshotDiagnosticCode.unsupportedVersion,
    );
  });

  test('missing_required_fields_returns_null_snapshot', () {
    final implicitData = <String, dynamic>{
      'reading_resume_targets_v1': {
        '0:series-1': {
          'version': 1,
          'target': {
            'seriesId': 'series-1',
            'sourceRefId': 'local:local:series-1:_',
            'sourceRefType': 'local',
            'sourceKey': 'local',
            'pageIndex': 1,
            'updatedAtMs': 1,
          },
          'sourceRef': {
            'id': 'local:local:series-1:_',
            'type': 'local',
            'sourceKey': 'local',
            'refId': 'series-1',
          },
        },
      },
    };
    final store = ResumeTargetStore(implicitData);
    final result = store.readWithDiagnostic('series-1', ComicType.local);
    expect(result.snapshot, isNull);
    expect(
      result.diagnostic,
      ResumeSnapshotDiagnosticCode.missingRequiredField,
    );
  });

  test('snapshot_payload_does_not_store_secrets', () {
    final implicitData = <String, dynamic>{};
    final store = ResumeTargetStore(implicitData);
    final ref = SourceRef.fromLegacyRemote(
      sourceKey: 'copymanga',
      comicId: 'series-1',
      chapterId: 'ch-1',
    );

    store.write(
      comicId: 'series-1',
      type: ComicType(999001),
      chapter: 1,
      group: null,
      page: 1,
      sourceRef: ref,
    );

    final raw = (implicitData['reading_resume_targets_v1']
        as Map<String, dynamic>)['999001:series-1'] as Map<String, dynamic>;
    final encoded = raw.toString().toLowerCase();
    expect(encoded.contains('token'), isFalse);
    expect(encoded.contains('cookie'), isFalse);
    expect(encoded.contains('password'), isFalse);
    expect(encoded.contains('authorization'), isFalse);
  });
}
