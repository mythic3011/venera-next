import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:venera/foundation/comic_type.dart';
import 'package:venera/foundation/local.dart';
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

    test('ensureImportCopyRootForTesting creates nested parent directories', () {
      final temp = Directory.systemTemp.createTempSync('import-root-helper');
      addTearDown(() => temp.deleteSync(recursive: true));
      final destination = '${temp.path}/runtimeRoot/local';

      expect(Directory(destination).existsSync(), isFalse);
      ensureImportCopyRootForTesting(destination);
      expect(Directory(destination).existsSync(), isTrue);
    });

    test('shouldAbortImportWhenNoComics follows empty-import failure contract', () {
      expect(
        shouldAbortImportWhenNoComics(
          imported: {null: const <LocalComic>[]},
          selectedFolder: null,
        ),
        isTrue,
      );
      expect(
        shouldAbortImportWhenNoComics(
          imported: {
            null: [
              LocalComic(
                id: '0',
                title: 'Comic A',
                subtitle: '',
                tags: const [],
                directory: '/tmp/comic-a',
                chapters: null,
                cover: 'cover.png',
                comicType: ComicType.local,
                downloadedChapters: const [],
                createdAt: DateTime.utc(2026, 5, 3),
              ),
            ],
          },
          selectedFolder: null,
        ),
        isFalse,
      );
    });
  });
}
