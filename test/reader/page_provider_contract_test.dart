import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:venera/foundation/db/unified_comics_store.dart';
import 'package:venera/foundation/reader/canonical_reader_pages.dart';
import 'package:venera/foundation/reader/canonical_remote_page_provider.dart';
import 'package:venera/foundation/reader/local_page_provider.dart';
import 'package:venera/foundation/reader/remote_page_provider.dart';
import 'package:venera/foundation/res.dart';
import 'package:venera/foundation/source_ref.dart';

void main() {
  test(
    'local_provider_rejects_non_local_ref_with_source_ref_type_mismatch',
    () async {
      final provider = LocalPageProvider(
        loadLocalPages:
            ({required localType, required localComicId, chapterId}) async => [
              'a',
            ],
      );
      final ref = SourceRef.fromLegacyRemote(
        sourceKey: 'copymanga',
        comicId: 'c1',
        chapterId: 'ch1',
      );

      final res = await provider.loadPages(ref);
      expect(res.error, isTrue);
      expect(res.errorMessage, 'SOURCE_REF_TYPE_MISMATCH');
    },
  );

  test(
    'remote_provider_rejects_non_remote_ref_with_source_ref_type_mismatch',
    () async {
      final provider = RemotePageProvider(
        loadRemotePages:
            ({
              required sourceKey,
              required comicId,
              required chapterId,
            }) async => const Res(['a']),
      );
      final ref = SourceRef.fromLegacyLocal(
        localType: 'local',
        localComicId: 'c1',
        chapterId: 'ch1',
      );

      final res = await provider.loadPages(ref);
      expect(res.error, isTrue);
      expect(res.errorMessage, 'SOURCE_REF_TYPE_MISMATCH');
    },
  );

  test(
    'local_provider_reads_local_params_and_calls_local_manager_getImages',
    () async {
      String? gotType;
      String? gotComic;
      String? gotChapter;

      final provider = LocalPageProvider(
        loadLocalPages:
            ({required localType, required localComicId, chapterId}) async {
              gotType = localType;
              gotComic = localComicId;
              gotChapter = chapterId;
              return ['p1', 'p2'];
            },
      );

      final ref = SourceRef.fromLegacyLocal(
        localType: 'local',
        localComicId: 'comic-1',
        chapterId: 'ch-1',
      );

      final res = await provider.loadPages(ref);
      expect(res.error, isFalse);
      expect(res.data, ['p1', 'p2']);
      expect(gotType, 'local');
      expect(gotComic, 'comic-1');
      expect(gotChapter, 'ch-1');
    },
  );

  test(
    'local_provider_allows_missing_chapterId_for_legacy_local_open',
    () async {
      String? gotChapter;
      final provider = LocalPageProvider(
        loadLocalPages:
            ({required localType, required localComicId, chapterId}) async {
              gotChapter = chapterId;
              return ['p1'];
            },
      );

      final ref = SourceRef.fromLegacyLocal(
        localType: 'local',
        localComicId: 'comic-1',
        chapterId: null,
      );

      final res = await provider.loadPages(ref);
      expect(res.error, isFalse);
      expect(gotChapter, isNull);
    },
  );

  test(
    'remote_provider_reads_remote_params_and_calls_comic_source_loadComicPages',
    () async {
      String? gotSource;
      String? gotComic;
      String? gotChapter;

      final provider = RemotePageProvider(
        loadRemotePages:
            ({required sourceKey, required comicId, required chapterId}) async {
              gotSource = sourceKey;
              gotComic = comicId;
              gotChapter = chapterId;
              return const Res(['p1']);
            },
      );

      final ref = SourceRef.fromLegacyRemote(
        sourceKey: 'copymanga',
        comicId: 'comic-2',
        chapterId: 'ch-2',
      );

      final res = await provider.loadPages(ref);
      expect(res.error, isFalse);
      expect(res.data, ['p1']);
      expect(gotSource, 'copymanga');
      expect(gotComic, 'comic-2');
      expect(gotChapter, 'ch-2');
    },
  );

  test(
    'remote provider prefers canonical remote pages when available',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'venera-page-provider-canonical-',
      );
      final store = UnifiedComicsStore(p.join(tempDir.path, 'venera.db'));
      await store.init();
      try {
        await _insertCanonicalRemoteFixture(store);
        var liveCalls = 0;
        final provider = RemotePageProvider(
          canonicalRemotePageProvider: CanonicalRemotePageProvider(
            canonicalReaderPages: CanonicalReaderPages(store: store),
          ),
          loadRemotePages:
              ({
                required sourceKey,
                required comicId,
                required chapterId,
              }) async {
                liveCalls++;
                return const Res(['live-1']);
              },
        );
        final ref = SourceRef.fromLegacyRemote(
          sourceKey: 'picacg',
          comicId: 'comic-1',
          chapterId: 'chapter-1',
        );

        final res = await provider.loadPages(ref);
        expect(res.error, isFalse);
        expect(res.data, [
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
    },
  );

  test(
    'remote provider falls back to live loader when canonical state is missing',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'venera-page-provider-fallback-',
      );
      final store = UnifiedComicsStore(p.join(tempDir.path, 'venera.db'));
      await store.init();
      try {
        var liveCalls = 0;
        final provider = RemotePageProvider(
          canonicalRemotePageProvider: CanonicalRemotePageProvider(
            canonicalReaderPages: CanonicalReaderPages(store: store),
          ),
          loadRemotePages:
              ({
                required sourceKey,
                required comicId,
                required chapterId,
              }) async {
                liveCalls++;
                return const Res(['live-1']);
              },
        );
        final ref = SourceRef.fromLegacyRemote(
          sourceKey: 'picacg',
          comicId: 'missing-comic',
          chapterId: 'chapter-1',
        );

        final res = await provider.loadPages(ref);
        expect(res.error, isFalse);
        expect(res.data, ['live-1']);
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
