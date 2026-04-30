import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:venera/foundation/comic_detail/comic_detail.dart';
import 'package:venera/foundation/comic_source/comic_source.dart';
import 'package:venera/foundation/comic_type.dart';
import 'package:venera/foundation/db/unified_comics_store.dart';
import 'package:venera/foundation/reader/page_provider.dart';
import 'package:venera/foundation/reader/reader_resume_service.dart';
import 'package:venera/foundation/reader/reader_runtime_context.dart';
import 'package:venera/foundation/reader/reader_session_persistence.dart';
import 'package:venera/foundation/reader/reader_session_repository.dart';
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

  test('resume service loads canonical active tab source ref only', () async {
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
    } finally {
      await store.close();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    }
  });
}
