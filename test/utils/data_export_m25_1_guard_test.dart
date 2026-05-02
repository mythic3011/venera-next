import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('exportAppData default export excludes legacy cache sidecar and canonical cache metadata db', () {
    final file = File('lib/utils/data.dart');
    final text = file.readAsStringSync();

    expect(text.contains('zipFile.addFile("cache.db"'), isFalse);
    expect(text.contains('zipFile.addFile("data/venera.db"'), isFalse);
  });
}
