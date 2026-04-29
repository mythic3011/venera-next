import 'package:flutter_test/flutter_test.dart';
import 'package:venera/foundation/image_provider/reader_image.dart';
import 'package:venera/pages/reader/reader.dart';

void main() {
  test('build_reader_image_provider_keeps_requested_page', () {
    final provider = buildReaderImageProvider(
      imageKey: 'https://example.com/page-3.jpg',
      sourceKey: 'copymanga',
      comicId: 'comic-9',
      chapterId: 'ep-5',
      page: 3,
      enableResize: true,
    );

    expect(provider.page, 3);
    expect(provider.enableResize, isTrue);
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
      'imageKey=https://example.com/page-3.jpg comicId=comic-9 chapterId=ep-5 page=3 sourceKey=copymanga',
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
      'EMPTY_PAGE_LIST: loadMode=local comicId=comic-1 chapterIndex=2 chapterId=ch-2 sourceKey=local',
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
      'EMPTY_PAGE_LIST: loadMode=remote comicId=comic-9 chapterIndex=5 chapterId=ep-5 sourceKey=copymanga',
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
}
