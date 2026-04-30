import 'package:flutter_test/flutter_test.dart';
import 'package:venera/pages/reader/reader.dart';
import 'package:venera/foundation/source_ref.dart';

void main() {
  test('resolve_reader_open_source_ref_handles_missing_source_key_fail_closed', () {
    final resolved = resolveReaderOpenSourceRef(
      comicId: 'comic-1',
      explicitSourceRef: null,
      resumeSourceRef: null,
      sourceKey: null,
    );
    expect(resolved, isNull);
  });

  test('resolve_reader_open_source_ref_precedence_explicit_then_resume_then_legacy', () {
    final explicit = SourceRef.fromLegacyLocal(
      localType: 'local',
      localComicId: 'comic-1',
      chapterId: 'ch-1',
    );
    final resume = SourceRef.fromLegacyRemote(
      sourceKey: 'copymanga',
      comicId: 'comic-1',
      chapterId: 'ch-1',
    );

    final withExplicit = resolveReaderOpenSourceRef(
      comicId: 'comic-1',
      explicitSourceRef: explicit,
      resumeSourceRef: resume,
      sourceKey: 'another',
    );
    expect(withExplicit, isNotNull);
    expect(withExplicit!.id, explicit.id);

    final withResume = resolveReaderOpenSourceRef(
      comicId: 'comic-1',
      explicitSourceRef: null,
      resumeSourceRef: resume,
      sourceKey: 'another',
    );
    expect(withResume, isNotNull);
    expect(withResume!.id, resume.id);

    final withLegacy = resolveReaderOpenSourceRef(
      comicId: 'comic-1',
      explicitSourceRef: null,
      resumeSourceRef: null,
      sourceKey: 'copymanga',
    );
    expect(withLegacy, isNotNull);
    expect(withLegacy!.type, SourceRefType.remote);
    expect(withLegacy.sourceKey, 'copymanga');
  });

  test('legacy_history_ep_page_group_controls_initial_position_when_no_override', () {
    final position = resolveReaderInitialPosition(
      requestedEp: null,
      requestedPage: null,
      requestedGroup: null,
      historyEp: 7,
      historyPage: 12,
      historyGroup: 3,
    );

    expect(position.chapter, 7);
    expect(position.page, 12);
    expect(position.group, 3);
  });

  test('explicit_group_override_is_preserved_in_initial_position', () {
    final position = resolveReaderInitialPosition(
      requestedEp: 2,
      requestedPage: 4,
      requestedGroup: 5,
      historyEp: 7,
      historyPage: 12,
      historyGroup: 3,
    );

    expect(position.chapter, 2);
    expect(position.page, 4);
    expect(position.group, 5);
  });

  test('explicit_resume_remote_ref_is_not_reinterpreted_as_local', () {
    final remoteResume = SourceRef.fromLegacyRemote(
      sourceKey: 'unknown-remote',
      comicId: 'comic-1',
      chapterId: 'ch-9',
    );
    final resolved = resolveReaderOpenSourceRef(
      comicId: 'comic-1',
      explicitSourceRef: null,
      resumeSourceRef: remoteResume,
      sourceKey: 'local',
    );
    expect(resolved, isNotNull);
    expect(resolved!.type, SourceRefType.remote);
    expect(resolved.sourceKey, 'unknown-remote');
  });

  test('explicit_unknown_remote_snapshot_fails_closed_in_load_path', () {
    final remoteResume = SourceRef.fromLegacyRemote(
      sourceKey: 'unknown-remote',
      comicId: 'comic-1',
      chapterId: 'ch-9',
    );

    final result = resolveReaderLoadSourceRef(
      comicId: 'comic-1',
      explicitSourceRef: null,
      resumeSourceRef: remoteResume,
      sourceKey: 'local',
      sourceExists: (_) => false,
    );

    expect(result.error, isTrue);
    expect(result.errorMessage, 'SOURCE_NOT_AVAILABLE:unknown-remote');
  });
}
