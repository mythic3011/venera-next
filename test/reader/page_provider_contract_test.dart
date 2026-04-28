import 'package:flutter_test/flutter_test.dart';
import 'package:venera/foundation/reader/local_page_provider.dart';
import 'package:venera/foundation/reader/remote_page_provider.dart';
import 'package:venera/foundation/res.dart';
import 'package:venera/foundation/source_ref.dart';

void main() {
  test('local_provider_rejects_non_local_ref_with_source_ref_type_mismatch', () async {
    final provider = LocalPageProvider(
      loadLocalPages: ({required localType, required localComicId, chapterId}) async => ['a'],
    );
    final ref = SourceRef.fromLegacyRemote(
      sourceKey: 'copymanga',
      comicId: 'c1',
      chapterId: 'ch1',
    );

    final res = await provider.loadPages(ref);
    expect(res.error, isTrue);
    expect(res.errorMessage, 'SOURCE_REF_TYPE_MISMATCH');
  });

  test('remote_provider_rejects_non_remote_ref_with_source_ref_type_mismatch', () async {
    final provider = RemotePageProvider(
      loadRemotePages: ({required sourceKey, required comicId, required chapterId}) async => const Res(['a']),
    );
    final ref = SourceRef.fromLegacyLocal(
      localType: 'local',
      localComicId: 'c1',
      chapterId: 'ch1',
    );

    final res = await provider.loadPages(ref);
    expect(res.error, isTrue);
    expect(res.errorMessage, 'SOURCE_REF_TYPE_MISMATCH');
  });

  test('local_provider_reads_local_params_and_calls_local_manager_getImages', () async {
    String? gotType;
    String? gotComic;
    String? gotChapter;

    final provider = LocalPageProvider(
      loadLocalPages: ({required localType, required localComicId, chapterId}) async {
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
  });

  test('local_provider_allows_missing_chapterId_for_legacy_local_open', () async {
    String? gotChapter;
    final provider = LocalPageProvider(
      loadLocalPages: ({required localType, required localComicId, chapterId}) async {
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
  });

  test('remote_provider_reads_remote_params_and_calls_comic_source_loadComicPages', () async {
    String? gotSource;
    String? gotComic;
    String? gotChapter;

    final provider = RemotePageProvider(
      loadRemotePages: ({required sourceKey, required comicId, required chapterId}) async {
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
  });
}
