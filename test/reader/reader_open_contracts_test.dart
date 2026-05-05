import 'package:flutter_test/flutter_test.dart';
import 'package:venera/features/comic_detail/data/comic_detail_models.dart';
import 'package:venera/features/sources/comic_source/comic_source.dart';
import 'package:venera/foundation/diagnostics/diagnostics.dart';
import 'package:venera/foundation/comic_type.dart';
import 'package:venera/foundation/history.dart';
import 'package:venera/foundation/local.dart';
import 'package:venera/foundation/reader/reader_open_target.dart';
import 'package:venera/features/reader/presentation/reader.dart';
import 'package:venera/foundation/sources/source_ref.dart';
import 'package:venera/pages/comic_details_page/comic_page.dart';

class _TestHistoryModel with HistoryMixin {
  _TestHistoryModel({
    required this.title,
    required this.subTitle,
    required this.cover,
    required this.id,
    required this.historyType,
  });

  @override
  final String title;

  @override
  final String? subTitle;

  @override
  final String cover;

  @override
  final String id;

  @override
  final ComicType historyType;
}

void main() {
  setUp(() {
    AppDiagnostics.resetForTesting();
  });

  test(
    'resolve_reader_open_source_ref_handles_missing_source_key_fail_closed',
    () {
      final resolved = resolveReaderOpenSourceRef(
        comicId: 'comic-1',
        explicitSourceRef: null,
        resumeSourceRef: null,
        sourceKey: null,
      );
      expect(resolved, isNull);
    },
  );

  test(
    'resolve_reader_open_source_ref_precedence_explicit_then_resume_then_legacy',
    () {
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
    },
  );

  test('reader open request uses sourceRef id as canonical identity', () {
    final sourceRef = SourceRef.fromLegacyLocal(
      localType: 'local',
      localComicId: 'comic-local',
      chapterId: '1:__imported__',
    );
    const comicId = 'comic-local';

    final request = ReaderOpenRequest(
      comicId: comicId,
      sourceRef: sourceRef,
      sourceKey: sourceRef.sourceKey,
      initialEp: 1,
      initialPage: 2,
    );

    expect(request.sourceRefId, 'local:local:comic-local:1:__imported__');
  });

  test(
    'reader open request preserves diagnostics entrypoint without affecting source identity',
    () {
      final sourceRef = SourceRef.fromLegacyLocal(
        localType: 'local',
        localComicId: 'comic-local',
        chapterId: '1:__imported__',
      );
      final request = ReaderOpenRequest(
        comicId: 'comic-local',
        sourceRef: sourceRef,
        sourceKey: sourceRef.sourceKey,
        diagnosticEntrypoint: 'comic_detail.read',
        diagnosticCaller: 'ComicPageActions.read',
      );

      expect(request.sourceRefId, sourceRef.id);
      expect(request.sourceKey, sourceRef.sourceKey);
      expect(request.diagnosticEntrypoint, 'comic_detail.read');
      expect(request.diagnosticCaller, 'ComicPageActions.read');
    },
  );

  test('reader open request derives sourceKey from sourceRef when present', () {
    final request = ReaderOpenRequest(
      comicId: 'comic-local',
      sourceRef: SourceRef.fromLegacyLocal(
        localType: 'local',
        localComicId: 'comic-local',
        chapterId: '1:__imported__',
      ),
      initialEp: 1,
    );

    expect(request.sourceKey, 'local');
  });

  test('reader open request rejects sourceRef and sourceKey mismatch', () {
    expect(
      () => ReaderOpenRequest(
        comicId: 'comic-local',
        sourceRef: SourceRef.fromLegacyLocal(
          localType: 'local',
          localComicId: 'comic-local',
          chapterId: '1:__imported__',
        ),
        sourceKey: 'copymanga',
      ),
      throwsA(
        isA<ReaderOpenRequestIdentityError>().having(
          (error) => error.code,
          'code',
          ReaderOpenRequestIdentityErrorCode.sourceKeyMismatch,
        ),
      ),
    );
  });

  test('local reader open request rejects mismatched local comic id', () {
    expect(
      () => ReaderOpenRequest(
        comicId: 'comic-b',
        sourceRef: SourceRef.fromLegacyLocal(
          localType: 'local',
          localComicId: 'comic-a',
          chapterId: '1:__imported__',
        ),
      ),
      throwsA(
        isA<ReaderOpenRequestIdentityError>().having(
          (error) => error.code,
          'code',
          ReaderOpenRequestIdentityErrorCode.localComicIdMismatch,
        ),
      ),
    );
  });

  test(
    'local reader open request rejects unresolved local target before dispatch',
    () {
      expect(
        () => ReaderOpenRequest(
          comicId: 'comic-local',
          sourceRef: SourceRef.fromLegacyLocal(
            localType: 'local',
            localComicId: 'comic-local',
            chapterId: null,
          ),
        ),
        throwsA(
          isA<ReaderOpenRequestIdentityError>().having(
            (error) => error.code,
            'code',
            ReaderOpenRequestIdentityErrorCode.unresolvedLocalTarget,
          ),
        ),
      );

      final event = DevDiagnosticsApi.recent(channel: 'reader.route').single;
      expect(event.message, 'reader.route.unresolved_target');
      expect(event.data['comicId'], 'comic-local');
      expect(event.data['sourceRefId'], 'local:local:comic-local:_');
      expect(event.data['reason'], 'missingLocalChapterId');
    },
  );

  test(
    'ReaderWithLoading normalizes legacy id sourceKey initialEp into ReaderOpenRequest',
    () {
      final request = normalizeLegacyReaderOpenRequest(
        comicId: 'comic-1',
        explicitSourceRef: null,
        sourceKey: 'copymanga',
        initialEp: 3,
        initialPage: 7,
        initialGroup: 2,
      );

      expect(request.comicId, 'comic-1');
      expect(request.sourceRef, isNotNull);
      expect(request.sourceRef!.sourceKey, 'copymanga');
      expect(request.initialEp, 3);
      expect(request.initialPage, 7);
      expect(request.initialGroup, 2);
    },
  );

  test('legacy sourceKey path remains supported when sourceRef is absent', () {
    final request = ReaderOpenRequest(
      comicId: 'comic-legacy',
      sourceKey: 'copymanga',
      initialEp: 2,
      initialPage: 6,
    );

    expect(request.comicId, 'comic-legacy');
    expect(request.sourceRef, isNull);
    expect(request.sourceKey, 'copymanga');
  });

  test(
    'ReaderWithLoading accepts resolved ReaderOpenRequest as single contract',
    () {
      final request = ReaderOpenRequest(
        comicId: 'comic-local',
        sourceRef: SourceRef.fromLegacyLocal(
          localType: 'local',
          localComicId: 'comic-local',
          chapterId: '1:__imported__',
        ),
        sourceKey: 'local',
        initialEp: 1,
        initialPage: 3,
      );

      final widget = ReaderWithLoading.fromRequest(request: request);

      expect(widget.normalizedRequest.comicId, 'comic-local');
      expect(
        widget.normalizedRequest.sourceRefId,
        'local:local:comic-local:1:__imported__',
      );
      expect(widget.normalizedRequest.initialPage, 3);
    },
  );

  test(
    'legacy ReaderWithLoading constructor remains supported during migration',
    () {
      final widget = ReaderWithLoading(
        id: 'comic-legacy',
        sourceKey: 'copymanga',
        initialEp: 2,
        initialPage: 6,
      );

      expect(widget.normalizedRequest.comicId, 'comic-legacy');
      expect(widget.normalizedRequest.sourceRef, isNotNull);
      expect(widget.normalizedRequest.sourceKey, 'copymanga');
      expect(widget.normalizedRequest.initialEp, 2);
      expect(widget.normalizedRequest.initialPage, 6);
    },
  );

  test(
    'legacy_history_ep_page_group_controls_initial_position_when_no_override',
    () {
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
    },
  );

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

  test(
    'ReaderWithLoading build diagnostics use resolved local imported sourceRef after loadData',
    () {
      final resolvedLocalImportedRef = SourceRef.fromLegacyLocal(
        localType: 'local',
        localComicId: '1',
        chapterId: '1:__imported__',
      );

      final diagnosticRef = resolveReaderDiagnosticSourceRef(
        readerPropsSourceRef: null,
        resolvedSourceRefForDiagnostics: resolvedLocalImportedRef,
        widgetSourceRef: null,
        comicId: '1',
        sourceKey: 'local',
      );

      expect(diagnosticRef, isNotNull);
      expect(diagnosticRef!.id, 'local:local:1:1:__imported__');
    },
  );

  test(
    'ReaderWithLoading content readerChildKey matches Reader open sourceRef id',
    () {
      final resolvedLocalImportedRef = SourceRef.fromLegacyLocal(
        localType: 'local',
        localComicId: '1',
        chapterId: '1:__imported__',
      );

      final childKey = buildReaderWithLoadingChildKey(
        comicId: '1',
        sourceRef: resolvedLocalImportedRef,
      );

      expect(childKey, 'reader:1:local:local:1:1:__imported__');
    },
  );

  test(
    'ReaderWithLoading does not build parent key from placeholder chapter id when sourceRef is resolved',
    () {
      final resolvedLocalImportedRef = SourceRef.fromLegacyLocal(
        localType: 'local',
        localComicId: '1',
        chapterId: '1:__imported__',
      );
      final request = normalizeLegacyReaderOpenRequest(
        comicId: '1',
        explicitSourceRef: resolvedLocalImportedRef,
        sourceKey: 'local',
        initialEp: 1,
      );

      final childKey = buildReaderWithLoadingChildKey(
        comicId: request.comicId,
        sourceRef: request.sourceRef!,
      );

      expect(childKey, 'reader:1:local:local:1:1:__imported__');
      expect(childKey, isNot('reader:1:local:local:1:_'));
    },
  );

  test(
    'ReaderWithLoading does not use legacy placeholder sourceRef when resolved sourceRef is available',
    () {
      final resolvedLocalImportedRef = SourceRef.fromLegacyLocal(
        localType: 'local',
        localComicId: '1',
        chapterId: '1:__imported__',
      );
      final legacyPlaceholderRef = SourceRef.fromLegacy(
        comicId: '1',
        sourceKey: 'local',
      );

      final diagnosticRef = resolveReaderDiagnosticSourceRef(
        readerPropsSourceRef: null,
        resolvedSourceRefForDiagnostics: resolvedLocalImportedRef,
        widgetSourceRef: legacyPlaceholderRef,
        comicId: '1',
        sourceKey: 'local',
      );

      expect(diagnosticRef, isNotNull);
      expect(diagnosticRef!.id, 'local:local:1:1:__imported__');
      expect(diagnosticRef.id, isNot(legacyPlaceholderRef.id));
    },
  );

  test(
    'canonical active tab seeds compatibility history without legacy lookup',
    () {
      final history = buildReaderCompatibilityHistory(
        model: _TestHistoryModel(
          title: 'Comic 1',
          subTitle: '',
          cover: '',
          id: 'comic-1',
          historyType: ComicType.local,
        ),
        chapters: const ComicChapters({
          'chapter-1': 'Episode 1',
          'chapter-2': 'Episode 2',
        }),
        canonicalActiveTab: ReaderTabVm(
          tabId: 'tab-1',
          currentChapterId: 'chapter-2',
          currentPageIndex: 9,
          sourceRef: SourceRef.fromLegacyLocal(
            localType: 'local',
            localComicId: 'comic-1',
            chapterId: 'chapter-2',
          ),
          loadMode: ReaderTabLoadMode.localLibrary,
          isActive: true,
        ),
      );

      expect(history.ep, 2);
      expect(history.page, 9);
      expect(history.group, isNull);
    },
  );

  test(
    'missing canonical active tab falls back to empty compatibility history',
    () {
      final history = buildReaderCompatibilityHistory(
        model: _TestHistoryModel(
          title: 'Comic 1',
          subTitle: '',
          cover: '',
          id: 'comic-1',
          historyType: ComicType.local,
        ),
        chapters: const ComicChapters({'chapter-1': 'Episode 1'}),
        canonicalActiveTab: null,
      );

      expect(history.ep, 0);
      expect(history.page, 0);
    },
  );

  test(
    'detail and history reader requests produce the same resolved local reader identity',
    () {
      final resolvedLocalRef = SourceRef.fromLegacyLocal(
        localType: 'local',
        localComicId: 'comic-local',
        chapterId: '1:__imported__',
      );
      final detailRequest = buildComicDetailReaderOpenRequest(
        comic: ComicDetails.fromJson({
          'title': 'Local Comic',
          'sourceKey': 'local',
          'comicId': 'comic-local',
        }),
        sourceRef: resolvedLocalRef,
        ep: 1,
        page: 5,
        group: null,
      );
      final localComic = LocalComic(
        id: 'comic-local',
        title: 'Local Comic',
        subtitle: 'Imported',
        tags: const <String>[],
        directory: '/tmp/comic-local',
        chapters: ComicChapters({'1:__imported__': 'Imported Chapter'}),
        cover: 'cover.jpg',
        comicType: ComicType.local,
        downloadedChapters: const <String>['1:__imported__'],
        createdAt: DateTime.utc(2026, 5, 3),
      );
      final historyRequest = buildLocalComicReaderOpenRequest(
        comic: localComic,
        history: History.fromModel(model: localComic, ep: 1, page: 5),
        firstDownloadedChapter: 1,
        firstDownloadedChapterGroup: null,
        resumeTarget: ReaderOpenTarget(sourceRef: resolvedLocalRef),
      );

      expect(detailRequest.sourceRef.id, historyRequest.sourceRefId);
      expect(
        detailRequest.sourceRef.id,
        'local:local:comic-local:1:__imported__',
      );
    },
  );

  test('comic detail request normalizes through ReaderOpenRequest', () {
    final sourceRef = SourceRef.fromLegacyLocal(
      localType: 'local',
      localComicId: 'comic-local',
      chapterId: '1:__imported__',
    );
    final detailRequest = buildComicDetailReaderOpenRequest(
      comic: ComicDetails.fromJson({
        'title': 'Local Comic',
        'sourceKey': 'local',
        'comicId': 'comic-local',
      }),
      sourceRef: sourceRef,
      ep: 1,
      page: 2,
      group: null,
    );

    final widget = ReaderWithLoading.fromRequest(
      request: detailRequest.toReaderOpenRequest(),
    );

    expect(widget.normalizedRequest.comicId, 'comic-local');
    expect(
      widget.normalizedRequest.sourceRefId,
      'local:local:comic-local:1:__imported__',
    );
    expect(widget.normalizedRequest.initialPage, 2);
  });

  test('history continue request normalizes through ReaderOpenRequest', () {
    final comic = LocalComic(
      id: 'comic-local',
      title: 'Local Comic',
      subtitle: 'Imported',
      tags: const <String>[],
      directory: '/tmp/comic-local',
      chapters: ComicChapters({'1:__imported__': 'Imported Chapter'}),
      cover: 'cover.jpg',
      comicType: ComicType.local,
      downloadedChapters: const <String>['1:__imported__'],
      createdAt: DateTime.utc(2026, 5, 3),
    );
    final sourceRef = SourceRef.fromLegacyLocal(
      localType: 'local',
      localComicId: 'comic-local',
      chapterId: '1:__imported__',
    );
    final request = buildLocalComicReaderOpenRequest(
      comic: comic,
      history: History.fromModel(model: comic, ep: 1, page: 4),
      firstDownloadedChapter: 1,
      firstDownloadedChapterGroup: null,
      resumeTarget: ReaderOpenTarget(sourceRef: sourceRef),
    );

    final widget = ReaderWithLoading.fromRequest(request: request);

    expect(widget.normalizedRequest.comicId, 'comic-local');
    expect(
      widget.normalizedRequest.sourceRefId,
      'local:local:comic-local:1:__imported__',
    );
    expect(widget.normalizedRequest.initialPage, 4);
  });
}
