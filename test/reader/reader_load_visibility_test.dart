import 'package:flutter_test/flutter_test.dart';
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
}
