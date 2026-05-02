import 'package:flutter_test/flutter_test.dart';
import 'package:venera/foundation/comic_type.dart';
import 'package:venera/foundation/diagnostics/diagnostics.dart';
import 'package:venera/foundation/image_provider/reader_image.dart';
import 'package:venera/features/reader/presentation/reader.dart';
import 'package:venera/foundation/source_ref.dart';

void main() {
  setUp(() {
    AppDiagnostics.configureSinksForTesting(const []);
  });

  tearDown(() {
    AppDiagnostics.resetForTesting();
  });

  test('build_reader_image_provider_keeps_requested_page', () {
    final provider = buildReaderImageProvider(
      imageKey: 'https://example.com/page-3.jpg',
      sourceRef: SourceRef.fromLegacyRemote(
        sourceKey: 'copymanga',
        comicId: 'comic-9',
        chapterId: 'ep-5',
      ),
      canonicalComicId: 'remote:copymanga:comic-9',
      upstreamComicRefId: 'comic-9',
      chapterRefId: 'ep-5',
      page: 3,
      enableResize: true,
    );

    expect(provider.page, 3);
    expect(provider.enableResize, isTrue);
  });

  test('reader image provider emits local page terminal diagnostics', () {
    buildReaderImageProvider(
      imageKey: 'file:///tmp/page-1.jpg',
      sourceRef: SourceRef.fromLegacyLocal(
        localType: 'local',
        localComicId: 'comic-1',
        chapterId: 'comic-1:__imported__',
      ),
      canonicalComicId: 'comic-1',
      upstreamComicRefId: 'comic-1',
      chapterRefId: 'comic-1:__imported__',
      page: 1,
      enableResize: true,
    );

    final event = DevDiagnosticsApi.recent(
      channel: 'reader.render',
    ).singleWhere((event) => event.message == 'reader.render.page.attached');
    expect(event.data['page'], 1);
    expect(event.data['chapterId'], 'comic-1:__imported__');
    final providerCreated = DevDiagnosticsApi.recent(channel: 'reader.render')
        .singleWhere(
          (event) => event.message == 'reader.render.page.provider.created',
        );
    expect(providerCreated.data['loadMode'], 'local');
    expect(providerCreated.data['imageKey'], 'file:///tmp/page-1.jpg');
  });

  test('reader image provider emits remote page terminal diagnostics', () {
    buildReaderImageProvider(
      imageKey: 'https://example.com/page-3.jpg',
      sourceRef: SourceRef.fromLegacyRemote(
        sourceKey: 'copymanga',
        comicId: 'comic-9',
        chapterId: 'ep-5',
      ),
      canonicalComicId: 'remote:copymanga:comic-9',
      upstreamComicRefId: 'comic-9',
      chapterRefId: 'ep-5',
      page: 3,
      enableResize: true,
    );

    final messages = DevDiagnosticsApi.recent(
      channel: 'reader.render',
    ).map((event) => event.message);
    expect(messages, contains('reader.render.page.attached'));
    expect(messages, contains('reader.render.page.provider.created'));
    final providerCreated = DevDiagnosticsApi.recent(channel: 'reader.render')
        .singleWhere(
          (event) => event.message == 'reader.render.page.provider.created',
        );
    expect(providerCreated.data['loadMode'], 'remote');
    expect(providerCreated.data['imageKey'], 'https://example.com/page-3.jpg');
  });

  test('reader image diagnostics include comic chapter and source context', () {
    final context = readerImageLoadContextForTesting(
      imageKey: 'https://example.com/page-3.jpg',
      sourceKey: 'copymanga',
      comicId: 'comic-9',
      chapterId: 'ep-5',
      page: 3,
    );

    expect(
      context,
      'imageKey=https://example.com/page-3.jpg canonicalComicId=comic-9 upstreamComicRefId=comic-9 chapterRefId=ep-5 page=3 sourceKey=copymanga',
    );
  });

  test('empty local page list surfaces diagnostic with chapter context', () {
    final error = resolveReaderEmptyPageListError(
      images: const [],
      loadMode: 'local',
      comicId: 'comic-1',
      chapterIndex: 2,
      chapterId: 'ch-2',
      sourceKey: 'local',
    );

    expect(
      error,
      'EMPTY_PAGE_LIST: loadMode=local canonicalComicRefId=comic-1 chapterIndex=2 chapterId=ch-2 sourceKey=local',
    );
  });

  test('empty remote page list surfaces diagnostic with source key', () {
    final error = resolveReaderEmptyPageListError(
      images: const [],
      loadMode: 'remote',
      comicId: 'comic-9',
      chapterIndex: 5,
      chapterId: 'ep-5',
      sourceKey: 'copymanga',
    );

    expect(
      error,
      'EMPTY_PAGE_LIST: loadMode=remote canonicalComicRefId=comic-9 chapterIndex=5 chapterId=ep-5 sourceKey=copymanga',
    );
  });

  test('non-empty page list does not surface error', () {
    final error = resolveReaderEmptyPageListError(
      images: const ['p1'],
      loadMode: 'remote',
      comicId: 'comic-9',
      chapterIndex: 5,
      chapterId: 'ep-5',
      sourceKey: 'copymanga',
    );

    expect(error, isNull);
  });

  test('source unavailable errors include suffixed source diagnostics', () {
    expect(
      isReaderSourceUnavailableErrorForTesting('SOURCE_NOT_AVAILABLE'),
      isTrue,
    );
    expect(
      isReaderSourceUnavailableErrorForTesting(
        'SOURCE_NOT_AVAILABLE:Unknown:122396838',
      ),
      isTrue,
    );
    expect(
      isReaderSourceUnavailableErrorForTesting('LOCAL_ASSET_MISSING'),
      isFalse,
    );
  });

  test('unknown reader type falls back to local when local comic exists', () {
    final shouldLoadLocal = shouldLoadReaderPagesLocallyForTesting(
      type: ComicType.fromKey('Unknown:122396838'),
      comicId: '1',
      isDownloaded: (_, _) => false,
      hasLocalComic: (comicId) => comicId == '1',
    );
    final localTypeKey = readerLocalTypeKeyForTesting(
      type: ComicType.fromKey('Unknown:122396838'),
      comicId: '1',
      hasLocalComic: (comicId) => comicId == '1',
    );

    expect(shouldLoadLocal, isTrue);
    expect(localTypeKey, 'local');
  });

  test('unknown reader type stays remote when no local comic exists', () {
    final shouldLoadLocal = shouldLoadReaderPagesLocallyForTesting(
      type: ComicType.fromKey('Unknown:122396838'),
      comicId: 'missing',
      isDownloaded: (_, _) => false,
      hasLocalComic: (_) => false,
    );

    expect(shouldLoadLocal, isFalse);
  });
}
