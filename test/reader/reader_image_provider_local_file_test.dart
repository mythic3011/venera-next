import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:venera/foundation/image_provider/reader_image.dart';

void main() {
  test('file URI image keys normalize to readable local file paths', () {
    final tempDir = Directory.systemTemp.createTempSync(
      'venera_reader_image_path_test_',
    );
    addTearDown(() => tempDir.deleteSync(recursive: true));

    final file = File('${tempDir.path}/page.bin')..writeAsBytesSync([1, 2, 3]);
    final normalizedPath = readerImageFilePathForTesting('file://${file.path}');

    expect(normalizedPath, file.path);
    expect(File(normalizedPath).existsSync(), isTrue);
  });

  test('remote and relative image keys are not normalized as local paths', () {
    const httpsUrl = 'https://example.com/comic/page.jpg';
    const httpUrl = 'http://example.com/comic/page.jpg';
    const relativePath = 'images/page.jpg';

    expect(readerImageFilePathForTesting(httpsUrl), httpsUrl);
    expect(readerImageFilePathForTesting(httpUrl), httpUrl);
    expect(readerImageFilePathForTesting(relativePath), relativePath);
  });
}
