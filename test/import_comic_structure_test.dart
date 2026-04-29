import 'package:flutter_test/flutter_test.dart';
import 'package:venera/utils/import_comic.dart';

void main() {
  group('import comic structure helpers', () {
    test('isSupportedImageExtension is case-insensitive', () {
      expect(isSupportedImageExtension('JPG'), isTrue);
      expect(isSupportedImageExtension('WebP'), isTrue);
      expect(isSupportedImageExtension('txt'), isFalse);
    });

    test(
      'selectCoverPathForImport prefers root cover file among supported images',
      () {
        final cover = selectCoverPathForImport(
          rootFiles: const ['001.jpg', 'cover.PNG', 'notes.txt'],
          chapterFiles: const {},
        );

        expect(cover, 'cover.PNG');
      },
    );

    test(
      'selectCoverPathForImport falls back to first natural sorted chapter image',
      () {
        final cover = selectCoverPathForImport(
          rootFiles: const ['README.md'],
          chapterFiles: const {
            'chapter10': ['10.jpg', '2.jpg'],
            'chapter2': ['b.jpg', 'A.JPG'],
          },
        );

        expect(cover, 'chapter2/A.JPG');
      },
    );
  });
}
