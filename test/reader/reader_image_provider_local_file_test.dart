import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:venera/foundation/local.dart';
import 'package:venera/foundation/image_provider/reader_image.dart';
import 'package:venera/pages/reader/reader.dart';

void main() {
  test('file URI image keys normalize to readable local file paths', () {
    expect(readerImageFilePathForTesting('file:///tmp/a.jpg'), '/tmp/a.jpg');

    final tempDir = Directory.systemTemp.createTempSync(
      'venera_reader_image_path_test_',
    );
    addTearDown(() => tempDir.deleteSync(recursive: true));

    final file = File('${tempDir.path}/page.bin')..writeAsBytesSync([1, 2, 3]);
    final normalizedPath = readerImageFilePathForTesting('file://${file.path}');

    expect(normalizedPath, file.path);
    expect(File(normalizedPath).existsSync(), isTrue);
  });

  test('file URI image key with spaces normalizes correctly', () {
    final tempDir = Directory.systemTemp.createTempSync(
      'venera_reader_image_path_test_',
    );
    addTearDown(() => tempDir.deleteSync(recursive: true));

    final file = File('${tempDir.path}/page with spaces.bin')
      ..writeAsBytesSync([1, 2, 3]);
    final uri = file.uri.toString();
    final normalizedPath = readerImageFilePathForTesting(uri);

    expect(normalizedPath, file.path);
    expect(File(normalizedPath).existsSync(), isTrue);
  });

  test('file URI with absolute path normalizes to local path', () {
    expect(readerImageFilePathForTesting('file:///tmp/a.jpg'), '/tmp/a.jpg');
  });

  test('remote and relative image keys are not normalized as local paths', () {
    const httpsUrl = 'https://example.com/comic/page.jpg';
    const httpUrl = 'http://example.com/comic/page.jpg';
    const relativePath = 'images/page.jpg';

    expect(readerImageFilePathForTesting(httpsUrl), httpsUrl);
    expect(readerImageFilePathForTesting(httpUrl), httpUrl);
    expect(readerImageFilePathForTesting(relativePath), relativePath);
  });

  test('local produced key roundtrips through reader file path parsing', () {
    final tempDir = Directory.systemTemp.createTempSync(
      'venera_local_page_uri_key_test_',
    );
    addTearDown(() => tempDir.deleteSync(recursive: true));

    final file = File('${tempDir.path}/中文 page 1.bin')
      ..writeAsBytesSync([7, 8, 9]);
    final imageKey = localPageImageKey(file);

    expect(imageKey, file.uri.toString());
    expect(readerImageFilePathForTesting(imageKey), file.path);
  });

  test('reader page local byte reads decode file URIs with spaces', () async {
    final tempDir = Directory.systemTemp.createTempSync(
      'venera_reader_page_bytes_space_test_',
    );
    addTearDown(() => tempDir.deleteSync(recursive: true));

    final expectedBytes = [1, 2, 3, 4];
    final file = File('${tempDir.path}/page with spaces.bin')
      ..writeAsBytesSync(expectedBytes);

    final bytes = await readReaderImageBytesForTesting(
      imageKey: file.uri.toString(),
      sourceKey: 'local',
      comicId: 'comic-space',
      chapterId: 'chapter-1',
    );

    expect(bytes, expectedBytes);
  });

  test(
    'reader page local byte reads decode percent-encoded file URIs',
    () async {
      final tempDir = Directory.systemTemp.createTempSync(
        'venera_reader_page_bytes_percent_test_',
      );
      addTearDown(() => tempDir.deleteSync(recursive: true));

      final expectedBytes = [5, 6, 7, 8];
      final file = File('${tempDir.path}/chapter #1%20.bin')
        ..writeAsBytesSync(expectedBytes);
      final uri = Uri(
        scheme: 'file',
        pathSegments: [...file.uri.pathSegments],
      ).toString();

      final bytes = await readReaderImageBytesForTesting(
        imageKey: uri,
        sourceKey: 'local',
        comicId: 'comic-percent',
        chapterId: 'chapter-2',
      );

      expect(bytes, expectedBytes);
    },
  );

  test('reader page local byte reads decode non-ascii file URIs', () async {
    final tempDir = Directory.systemTemp.createTempSync(
      'venera_reader_page_bytes_unicode_test_',
    );
    addTearDown(() => tempDir.deleteSync(recursive: true));

    final expectedBytes = [9, 10, 11, 12];
    final file = File('${tempDir.path}/中文 圖像.bin')
      ..writeAsBytesSync(expectedBytes);

    final bytes = await readReaderImageBytesForTesting(
      imageKey: file.uri.toString(),
      sourceKey: 'local',
      comicId: 'comic-unicode',
      chapterId: 'chapter-3',
    );

    expect(bytes, expectedBytes);
  });
}
