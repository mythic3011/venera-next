import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:venera/foundation/comic_detail/comic_detail.dart';
import 'package:venera/features/sources/comic_source/comic_source.dart';
import 'package:venera/foundation/comic_type.dart';
import 'package:venera/foundation/db/unified_comics_store.dart';
import 'package:venera/foundation/diagnostics/diagnostics.dart';
import 'package:venera/foundation/reader/page_provider.dart';
import 'package:venera/foundation/reader/resume_target_store.dart';
import 'package:venera/features/reader/data/reader_resume_service.dart';
import 'package:venera/features/reader/data/reader_runtime_context.dart';
import 'package:venera/features/reader/data/reader_session_persistence.dart';
import 'package:venera/features/reader/data/reader_session_repository.dart';
import 'package:venera/foundation/reader/source_ref_resolver.dart';
import 'package:venera/foundation/res.dart';
import 'package:venera/foundation/source_ref.dart';
import 'package:venera/pages/comic_details_page/comic_page.dart';

class _SpyProvider implements ReadablePageProvider {
  int calls = 0;

  @override
  Future<Res<List<String>>> loadPages(SourceRef ref) async {
    calls++;
    return const Res(['ok']);
  }
}

void main() {
  tearDown(() {
    AppDiagnostics.resetForTesting();
  });

  test(
    'local_continue_reading_remains_local_with_linked_remote_source',
    () async {
      final local = _SpyProvider();
      final remote = _SpyProvider();
      final resolver = SourceRefResolver(
        localProvider: local,
        remoteProviderFactory: (_) => remote,
        sourceExists: (_) => true,
      );

      final localResumeRef = SourceRef.fromLegacyLocal(
        localType: 'local',
        localComicId: 'series-1',
        chapterId: 'chapter-1',
      );

      await resolver.resolve(localResumeRef).loadPages(localResumeRef);

      expect(local.calls, 1);
      expect(remote.calls, 0);
    },
  );

  test('linked_remote_source_does_not_hijack_local_resume_dispatch', () async {
    final local = _SpyProvider();
    final remote = _SpyProvider();
    final resolver = SourceRefResolver(
      localProvider: local,
      remoteProviderFactory: (_) => remote,
      sourceExists: (_) => true,
    );

    final localResumeRef = SourceRef.fromLegacyLocal(
      localType: 'local',
      localComicId: 'series-1',
      chapterId: 'chapter-1',
    );
    final linkedRemoteRef = SourceRef.fromLegacyRemote(
      sourceKey: 'copymanga',
      comicId: 'series-1',
      chapterId: 'chapter-1',
    );

    // Simulate presence of remote link; resume still uses the local snapshot ref.
    expect(linkedRemoteRef.type, SourceRefType.remote);
    await resolver.resolve(localResumeRef).loadPages(localResumeRef);

    expect(local.calls, 1);
    expect(remote.calls, 0);
  });

  test('remote_continue_reading_remains_remote_dispatch', () async {
    final local = _SpyProvider();
    final remote = _SpyProvider();
    final resolver = SourceRefResolver(
      localProvider: local,
      remoteProviderFactory: (_) => remote,
      sourceExists: (_) => true,
    );

    final remoteResumeRef = SourceRef.fromLegacyRemote(
      sourceKey: 'copymanga',
      comicId: 'series-2',
      chapterId: 'chapter-3',
    );

    await resolver.resolve(remoteResumeRef).loadPages(remoteResumeRef);

    expect(local.calls, 0);
    expect(remote.calls, 1);
  });

  test('continue read preserves saved resume target chapter id', () {
    final resumeRef = SourceRef.fromLegacyRemote(
      sourceKey: 'copymanga',
      comicId: 'comic-2',
      chapterId: 'ch-2',
    );

    final resolved = resolveComicDetailsReadSourceRef(
      comicId: 'comic-2',
      sourceKey: 'copymanga',
      chapters: const ComicChapters({'ch-1': 'Episode 1', 'ch-2': 'Episode 2'}),
      ep: 2,
      group: null,
      resumeSourceRef: resumeRef,
    );

    expect(identical(resolved, resumeRef), isTrue);
    expect(resolved.params['chapterId'], 'ch-2');
  });

  test('canonical active tab wins over legacy resume source ref', () {
    final canonicalActiveTab = ReaderTabVm(
      tabId: 'tab-1',
      currentChapterId: 'chapter-5',
      currentPageIndex: 12,
      sourceRef: SourceRef.fromLegacyRemote(
        sourceKey: 'copymanga',
        comicId: 'series-3',
        chapterId: 'chapter-5',
      ),
      loadMode: ReaderTabLoadMode.remoteSource,
      isActive: true,
    );

    final preferred = choosePreferredResumeSourceRefForTesting(
      canonicalActiveTab: canonicalActiveTab,
    );

    expect(preferred, isNotNull);
    expect(preferred!.type, SourceRefType.remote);
    expect(preferred.params['chapterId'], 'chapter-5');
  });

  test(
    'resume service returns null when no canonical active tab exists',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'venera-reader-resume-empty-',
      );
      final store = UnifiedComicsStore(p.join(tempDir.path, 'venera.db'));
      await store.init();
      try {
        final service = ReaderResumeService(
          readerSessions: ReaderSessionRepository(store: store),
        );

        final preferred = await service.loadPreferredResumeSourceRef(
          'series-4',
          ComicType.local,
        );

        expect(preferred, isNull);
      } finally {
        await store.close();
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      }
    },
  );

  test('ReaderResumeService uses legacy fallback only when fallback loader is injected', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'venera-reader-resume-no-injected-fallback-',
    );
    final store = UnifiedComicsStore(p.join(tempDir.path, 'venera.db'));
    await store.init();
    try {
      var fallbackCalls = 0;
      final serviceWithoutFallback = ReaderResumeService(
        readerSessions: ReaderSessionRepository(store: store),
      );
      final preferredWithoutFallback =
          await serviceWithoutFallback.loadPreferredResumeSourceRef(
            'series-no-fallback',
            ComicType.local,
          );

      expect(preferredWithoutFallback, isNull);
      expect(fallbackCalls, 0);

      final legacyRef = SourceRef.fromLegacyLocal(
        localType: 'local',
        localComicId: 'series-no-fallback',
        chapterId: 'chapter-3',
      );
      final serviceWithFallback = ReaderResumeService(
        readerSessions: ReaderSessionRepository(store: store),
        loadLegacyResumeSourceRef: (comicId, type) async {
          fallbackCalls++;
          return legacyRef;
        },
      );
      final preferredWithFallback =
          await serviceWithFallback.loadPreferredResumeSourceRef(
            'series-no-fallback',
            ComicType.local,
          );

      expect(preferredWithFallback?.id, legacyRef.id);
      expect(fallbackCalls, 1);
    } finally {
      await store.close();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    }
  });

  test('resume service emits legacy fallback hit when canonical session misses', () async {
    AppDiagnostics.configureSinksForTesting(const []);
    final tempDir = await Directory.systemTemp.createTemp(
      'venera-reader-resume-legacy-hit-',
    );
    final store = UnifiedComicsStore(p.join(tempDir.path, 'venera.db'));
    await store.init();
    try {
      final legacyRef = SourceRef.fromLegacyLocal(
        localType: 'local',
        localComicId: 'series-legacy',
        chapterId: 'chapter-7',
      );
      final preferred = await ReaderResumeService(
        readerSessions: ReaderSessionRepository(store: store),
        loadLegacyResumeSourceRef: (comicId, type) async => legacyRef,
      ).loadPreferredResumeSourceRef('series-legacy', ComicType.local);

      expect(preferred?.id, legacyRef.id);
      final events = DevDiagnosticsApi.recent(channel: 'reader.session');
      expect(
        events.any(
          (event) =>
              event.message == 'reader.session.load.legacy_fallback_hit' &&
              event.data['fallbackSource'] == 'reading_resume_targets_v1',
        ),
        isTrue,
      );
    } finally {
      await store.close();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    }
  });

  test('legacy resume target fallback still reads reading_resume_targets_v1 when injected', () async {
    AppDiagnostics.configureSinksForTesting(const []);
    final implicitData = <String, dynamic>{};
    final store = ResumeTargetStore(implicitData);
    final legacyRef = SourceRef.fromLegacyLocal(
      localType: 'local',
      localComicId: 'series-injected-legacy',
      chapterId: 'chapter-4',
    );
    store.write(
      comicId: 'series-injected-legacy',
      type: ComicType.local,
      chapter: 4,
      group: null,
      page: 9,
      sourceRef: legacyRef,
    );

    final tempDir = await Directory.systemTemp.createTemp(
      'venera-reader-resume-injected-legacy-',
    );
    final dbStore = UnifiedComicsStore(p.join(tempDir.path, 'venera.db'));
    await dbStore.init();
    try {
      final preferred = await ReaderResumeService(
        readerSessions: ReaderSessionRepository(store: dbStore),
        loadLegacyResumeSourceRef: (comicId, type) async =>
            store.readWithDiagnostic(comicId, type).snapshot?.sourceRef,
      ).loadPreferredResumeSourceRef(
        'series-injected-legacy',
        ComicType.local,
      );

      expect(preferred?.id, legacyRef.id);
      final events = DevDiagnosticsApi.recent(channel: 'reader.session');
      expect(
        events.any(
          (event) =>
              event.message == 'reader.session.load.legacy_fallback_hit' &&
              event.data['fallbackSource'] == 'reading_resume_targets_v1',
        ),
        isTrue,
      );
    } finally {
      await dbStore.close();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    }
  });

  test('resume service emits legacy fallback miss when canonical and legacy both miss', () async {
    AppDiagnostics.configureSinksForTesting(const []);
    final tempDir = await Directory.systemTemp.createTemp(
      'venera-reader-resume-legacy-miss-',
    );
    final store = UnifiedComicsStore(p.join(tempDir.path, 'venera.db'));
    await store.init();
    try {
      final preferred = await ReaderResumeService(
        readerSessions: ReaderSessionRepository(store: store),
        loadLegacyResumeSourceRef: (_, __) async => null,
      ).loadPreferredResumeSourceRef('series-miss', ComicType.local);

      expect(preferred, isNull);
      final events = DevDiagnosticsApi.recent(channel: 'reader.session');
      expect(
        events.any(
          (event) =>
              event.message == 'reader.session.load.legacy_fallback_miss' &&
              event.data['fallbackSource'] == 'reading_resume_targets_v1',
        ),
        isTrue,
      );
    } finally {
      await store.close();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    }
  });

  test('resume service loads canonical active tab source ref only', () async {
    AppDiagnostics.configureSinksForTesting(const []);
    final tempDir = await Directory.systemTemp.createTemp(
      'venera-reader-resume-hit-',
    );
    final store = UnifiedComicsStore(p.join(tempDir.path, 'venera.db'));
    await store.init();
    try {
      await store.upsertComic(
        const ComicRecord(
          id: 'series-5',
          title: 'Series 5',
          normalizedTitle: 'series 5',
        ),
      );
      final repository = ReaderSessionRepository(store: store);
      final localRef = SourceRef.fromLegacyLocal(
        localType: 'local',
        localComicId: 'series-5',
        chapterId: 'chapter-6',
      );
      await persistReaderSessionContextForTesting(
        repository: repository,
        context: buildReaderRuntimeContextForTesting(
          comicId: 'series-5',
          type: ComicType.local,
          chapterIndex: 6,
          page: 11,
          chapterId: 'chapter-6',
          sourceRef: localRef,
        ),
      );

      final preferred = await ReaderResumeService(
        readerSessions: repository,
      ).loadPreferredResumeSourceRef('series-5', ComicType.local);

      expect(preferred, isNotNull);
      expect(preferred!.type, SourceRefType.local);
      expect(preferred.sourceKey, 'local');
      expect(preferred.params['chapterId'], 'chapter-6');
      final events = DevDiagnosticsApi.recent(channel: 'reader.session');
      expect(
        events.any(
          (event) =>
              event.message == 'reader.session.load.canonical_hit' &&
              event.data['tabId'] != null,
        ),
        isTrue,
      );
    } finally {
      await store.close();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    }
  });

  test('canonical reader session hit bypasses legacy fallback loader', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'venera-reader-resume-bypass-legacy-',
    );
    final store = UnifiedComicsStore(p.join(tempDir.path, 'venera.db'));
    await store.init();
    try {
      await store.upsertComic(
        const ComicRecord(
          id: 'series-bypass',
          title: 'Series Bypass',
          normalizedTitle: 'series bypass',
        ),
      );
      final repository = ReaderSessionRepository(store: store);
      final localRef = SourceRef.fromLegacyLocal(
        localType: 'local',
        localComicId: 'series-bypass',
        chapterId: 'chapter-8',
      );
      await persistReaderSessionContextForTesting(
        repository: repository,
        context: buildReaderRuntimeContextForTesting(
          comicId: 'series-bypass',
          type: ComicType.local,
          chapterIndex: 8,
          page: 5,
          chapterId: 'chapter-8',
          sourceRef: localRef,
        ),
      );
      var fallbackCalls = 0;

      final preferred = await ReaderResumeService(
        readerSessions: repository,
        loadLegacyResumeSourceRef: (comicId, type) async {
          fallbackCalls++;
          return SourceRef.fromLegacyLocal(
            localType: 'local',
            localComicId: comicId,
            chapterId: 'chapter-legacy',
          );
        },
      ).loadPreferredResumeSourceRef('series-bypass', ComicType.local);

      expect(preferred?.id, localRef.id);
      expect(fallbackCalls, 0);
    } finally {
      await store.close();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    }
  });

  test('detail progress compatibility history uses canonical active tab', () {
    final history = buildComicDetailCompatibilityHistoryForTesting(
      model: ComicDetails.fromJson({
        'title': 'Comic 1',
        'subtitle': '',
        'cover': '',
        'description': '',
        'tags': const <String, List<String>>{},
        'chapters': const {
          'chapter-1': 'Episode 1',
          'chapter-2': 'Episode 2',
        },
        'sourceKey': 'copymanga',
        'comicId': 'comic-1',
      }),
      chapters: const ComicChapters({
        'chapter-1': 'Episode 1',
        'chapter-2': 'Episode 2',
      }),
      canonicalActiveTab: ReaderTabVm(
        tabId: 'tab-1',
        currentChapterId: 'chapter-2',
        currentPageIndex: 8,
        sourceRef: SourceRef.fromLegacyRemote(
          sourceKey: 'copymanga',
          comicId: 'comic-1',
          chapterId: 'chapter-2',
        ),
        loadMode: ReaderTabLoadMode.remoteSource,
        isActive: true,
      ),
    );

    expect(history.ep, 2);
    expect(history.page, 8);
    expect(history.group, isNull);
  });
}
