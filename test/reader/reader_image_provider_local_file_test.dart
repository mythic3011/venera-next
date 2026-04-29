import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:venera/foundation/image_provider/reader_image.dart';
import 'package:venera/foundation/local.dart';

void main() {
  test('file URI with absolute path normalizes to local path', () {
    expect(
      readerImageFilePathForTesting('file:///tmp/a.jpg'),
      '/tmp/a.jpg',
    );
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

  test('file URI image key with Chinese characters normalizes correctly', () {
    final tempDir = Directory.systemTemp.createTempSync(
      'venera_reader_image_path_test_',
    );
    addTearDown(() => tempDir.deleteSync(recursive: true));

    final file = File('${tempDir.path}/中文頁面.bin')..writeAsBytesSync([4, 5, 6]);
    final uri = file.uri.toString();
    final normalizedPath = readerImageFilePathForTesting(uri);

    expect(normalizedPath, file.path);
    expect(File(normalizedPath).existsSync(), isTrue);
  });

  test('local produced file key roundtrips through reader image normalization', () {
    final tempDir = Directory.systemTemp.createTempSync(
      'venera_reader_image_path_test_',
    );
    addTearDown(() => tempDir.deleteSync(recursive: true));

    final file = File('${tempDir.path}/頁面 with spaces.bin')
      ..writeAsBytesSync([7, 8, 9]);
    final imageKey = localPageKeyForTesting(file);

    expect(imageKey, file.uri.toString());
    expect(readerImageFilePathForTesting(imageKey), file.path);
  });

  test('remote https image key remains unchanged', () {
    const httpsUrl = 'https://example.com/comic/page.jpg';
    expect(readerImageFilePathForTesting(httpsUrl), httpsUrl);
  });

  test('relative image key remains unchanged', () {
    const relativePath = 'images/page.jpg';
    expect(readerImageFilePathForTesting(relativePath), relativePath);
  });
}
