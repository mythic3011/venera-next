import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:venera/foundation/comic_source/comic_source.dart';
import 'package:venera/foundation/db/unified_comics_store.dart';
import 'package:venera/foundation/reader/canonical_reader_pages.dart';
import 'package:venera/foundation/reader/canonical_remote_page_provider.dart';
import 'package:venera/foundation/reader/page_provider.dart';
import 'package:venera/foundation/reader/reader_page_loader.dart';
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

Future<ReaderPageLoaderResult> _dispatch({
  required bool useSourceRefResolver,
  required SourceRef ref,
  required String loadMode,
  required Future<Res<List<String>>> Function() legacyLoadPages,
  required ReaderPageLoader loader,
}) async {
  return dispatchReaderPageLoad(
    useSourceRefResolver: useSourceRefResolver,
    loadMode: loadMode,
    legacyLoadPages: legacyLoadPages,
    loader: loader,
    sourceRef: ref,
  );
}

void main() {
  test('flag_off_uses_legacy_page_loading_path', () async {
    final local = _SpyProvider();
    final remote = _SpyProvider();
    var legacyCalls = 0;
    final loader = ReaderPageLoader(
      loadLocalPages:
          ({required localType, required localComicId, chapterId}) async {
            local.calls++;
            return ['resolver-local'];
          },
      loadRemotePages:
          ({required sourceKey, required comicId, required chapterId}) async {
            remote.calls++;
            return const Res(['resolver-remote']);
          },
      sourceExists: (_) => true,
    );
    final ref = SourceRef.fromLegacyLocal(
      localType: 'local',
      localComicId: 'comic-1',
      chapterId: 'ch-1',
    );

    await _dispatch(
      useSourceRefResolver: false,
      ref: ref,
      loadMode: 'local',
      legacyLoadPages: () async {
        legacyCalls++;
        return const Res(['legacy']);
      },
      loader: loader,
    );

    expect(legacyCalls, 1);
    expect(local.calls, 0);
    expect(remote.calls, 0);
  });

  test('flag_on_uses_resolver_page_loading_path', () async {
    final local = _SpyProvider();
    final remote = _SpyProvider();
    var legacyCalls = 0;
    final loader = ReaderPageLoader(
      loadLocalPages:
          ({required localType, required localComicId, chapterId}) async {
            local.calls++;
            return ['resolver-local'];
          },
      loadRemotePages:
          ({required sourceKey, required comicId, required chapterId}) async {
            remote.calls++;
            return const Res(['resolver-remote']);
          },
      sourceExists: (_) => true,
    );
    final ref = SourceRef.fromLegacyLocal(
      localType: 'local',
      localComicId: 'comic-1',
      chapterId: 'ch-1',
    );

    await _dispatch(
      useSourceRefResolver: true,
      ref: ref,
      loadMode: 'local',
      legacyLoadPages: () async {
        legacyCalls++;
        return const Res(['legacy']);
      },
      loader: loader,
    );

    expect(legacyCalls, 0);
    expect(local.calls, 1);
    expect(remote.calls, 0);
  });

  test('flag_on_local_ref_never_calls_remote_provider', () async {
    final local = _SpyProvider();
    final remote = _SpyProvider();
    final loader = ReaderPageLoader(
      loadLocalPages:
          ({required localType, required localComicId, chapterId}) async {
            local.calls++;
            return ['resolver-local'];
          },
      loadRemotePages:
          ({required sourceKey, required comicId, required chapterId}) async {
            remote.calls++;
            return const Res(['resolver-remote']);
          },
      sourceExists: (_) => true,
    );
    final ref = SourceRef.fromLegacyLocal(
      localType: 'local',
      localComicId: 'comic-1',
      chapterId: 'ch-1',
    );

    await _dispatch(
      useSourceRefResolver: true,
      ref: ref,
      loadMode: 'local',
      legacyLoadPages: () async => const Res(['legacy']),
      loader: loader,
    );

    expect(local.calls, 1);
    expect(remote.calls, 0);
  });

  test('flag_on_remote_ref_never_calls_local_provider', () async {
    final local = _SpyProvider();
    final remote = _SpyProvider();
    final loader = ReaderPageLoader(
      loadLocalPages:
          ({required localType, required localComicId, chapterId}) async {
            local.calls++;
            return ['resolver-local'];
          },
      loadRemotePages:
          ({required sourceKey, required comicId, required chapterId}) async {
            remote.calls++;
            return const Res(['resolver-remote']);
          },
      sourceExists: (_) => true,
    );
    final ref = SourceRef.fromLegacyRemote(
      sourceKey: 'copymanga',
      comicId: 'comic-2',
      chapterId: 'ch-2',
    );

    await _dispatch(
      useSourceRefResolver: true,
      ref: ref,
      loadMode: 'remote',
      legacyLoadPages: () async => const Res(['legacy']),
      loader: loader,
    );

    expect(local.calls, 0);
    expect(remote.calls, 1);
  });

  test(
    'direct chapter open rewrites stale resume ref to selected chapter id',
    () {
      final resumeRef = SourceRef.fromLegacyRemote(
        sourceKey: 'copymanga',
        comicId: 'comic-2',
        chapterId: 'ch-1',
      );

      final resolved = resolveComicDetailsReadSourceRef(
        comicId: 'comic-2',
        sourceKey: 'copymanga',
        chapters: const ComicChapters({
          'ch-1': 'Episode 1',
          'ch-2': 'Episode 2',
        }),
        ep: 2,
        group: null,
        resumeSourceRef: resumeRef,
      );

      expect(resolved.type, SourceRefType.remote);
      expect(resolved.sourceKey, 'copymanga');
      expect(resolved.params['chapterId'], 'ch-2');
      expect(resolved.id, isNot(resumeRef.id));
    },
  );

  test('remote dispatch prefers canonical pages when available', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'venera-reader-dispatch-canonical-',
    );
    final store = UnifiedComicsStore(p.join(tempDir.path, 'venera.db'));
    await store.init();
    try {
      await _insertCanonicalRemoteFixture(store);
      var liveCalls = 0;
      final loader = ReaderPageLoader(
        loadLocalPages:
            ({required localType, required localComicId, chapterId}) async => [
              'local',
            ],
        loadRemotePages:
            ({required sourceKey, required comicId, required chapterId}) async {
              liveCalls++;
              return const Res(['live']);
            },
        canonicalRemotePageProviderFactory: (_) => CanonicalRemotePageProvider(
          canonicalReaderPages: CanonicalReaderPages(store: store),
        ),
        sourceExists: (_) => true,
      );
      final result = await loader.load(
        SourceRef.fromLegacyRemote(
          sourceKey: 'picacg',
          comicId: 'comic-1',
          chapterId: 'chapter-1',
        ),
      );

      expect(result.res.error, isFalse);
      expect(result.res.data, [
        'https://img.example/2.jpg',
        'https://img.example/1.jpg',
      ]);
      expect(liveCalls, 0);
    } finally {
      await store.close();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    }
  });

  test(
    'remote dispatch falls back to live source when canonical state is absent',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'venera-reader-dispatch-fallback-',
      );
      final store = UnifiedComicsStore(p.join(tempDir.path, 'venera.db'));
      await store.init();
      try {
        var liveCalls = 0;
        final loader = ReaderPageLoader(
          loadLocalPages:
              ({required localType, required localComicId, chapterId}) async =>
                  ['local'],
          loadRemotePages:
              ({
                required sourceKey,
                required comicId,
                required chapterId,
              }) async {
                liveCalls++;
                return const Res(['live']);
              },
          canonicalRemotePageProviderFactory: (_) =>
              CanonicalRemotePageProvider(
                canonicalReaderPages: CanonicalReaderPages(store: store),
              ),
          sourceExists: (_) => true,
        );
        final result = await loader.load(
          SourceRef.fromLegacyRemote(
            sourceKey: 'picacg',
            comicId: 'missing-comic',
            chapterId: 'chapter-1',
          ),
        );

        expect(result.res.error, isFalse);
        expect(result.res.data, ['live']);
        expect(liveCalls, 1);
      } finally {
        await store.close();
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      }
    },
  );
}

Future<void> _insertCanonicalRemoteFixture(UnifiedComicsStore store) async {
  await store.upsertSourcePlatform(
    const SourcePlatformRecord(
      id: 'picacg',
      canonicalKey: 'picacg',
      displayName: 'Pica',
      kind: 'remote',
    ),
  );
  await store.upsertComic(
    const ComicRecord(
      id: 'remote:picacg:comic-1',
      title: 'Remote Comic',
      normalizedTitle: 'remote comic',
    ),
  );
  await store.upsertComicSourceLink(
    const ComicSourceLinkRecord(
      id: 'source_link:remote:picacg:comic-1',
      comicId: 'remote:picacg:comic-1',
      sourcePlatformId: 'picacg',
      sourceComicId: 'comic-1',
      isPrimary: true,
    ),
  );
  await store.upsertChapter(
    const ChapterRecord(
      id: 'remote:picacg:comic-1:chapter-1',
      comicId: 'remote:picacg:comic-1',
      chapterNo: 1,
      title: 'Chapter 1',
      normalizedTitle: 'chapter 1',
    ),
  );
  await store.upsertPage(
    const PageRecord(
      id: 'remote-page-a',
      chapterId: 'remote:picacg:comic-1:chapter-1',
      pageIndex: 0,
      localPath: 'https://img.example/1.jpg',
    ),
  );
  await store.upsertPage(
    const PageRecord(
      id: 'remote-page-b',
      chapterId: 'remote:picacg:comic-1:chapter-1',
      pageIndex: 1,
      localPath: 'https://img.example/2.jpg',
    ),
  );
  await store.upsertPageOrder(
    const PageOrderRecord(
      id: 'remote-order-1',
      chapterId: 'remote:picacg:comic-1:chapter-1',
      orderName: 'Source Default',
      normalizedOrderName: 'source default',
      orderType: 'source_default',
      isActive: true,
    ),
  );
  await store.replacePageOrderItems('remote-order-1', const [
    PageOrderItemRecord(
      pageOrderId: 'remote-order-1',
      pageId: 'remote-page-b',
      sortOrder: 0,
    ),
    PageOrderItemRecord(
      pageOrderId: 'remote-order-1',
      pageId: 'remote-page-a',
      sortOrder: 1,
    ),
  ]);
}
