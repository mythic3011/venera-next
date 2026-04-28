import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:venera/utils/import_sort.dart';

void main() {
  test('naturalCompare handles numeric ordering', () {
    final values = ['4 (10).jpg', '4 (2).jpg', '4 (1).jpg'];
    naturalSortStrings(values);
    expect(values, ['4 (1).jpg', '4 (2).jpg', '4 (10).jpg']);
  });

  test('naturalCompare handles mixed tokens', () {
    final values = ['NEST#10.zip', 'NEST#2.zip', 'NEST#1.zip'];
    naturalSortStrings(values);
    expect(values, ['NEST#1.zip', 'NEST#2.zip', 'NEST#10.zip']);
  });

  test('isHiddenOrMacMetadataPath filters mac metadata', () {
    expect(isHiddenOrMacMetadataPath('__MACOSX/a/._b.zip'), isTrue);
    expect(isHiddenOrMacMetadataPath('folder/.DS_Store'), isTrue);
    expect(isHiddenOrMacMetadataPath('folder/page-1.jpg'), isFalse);
  });

  test('naturalSortFiles sorts by file name', () {
    final files = [
      File('/tmp/10.jpg'),
      File('/tmp/2.jpg'),
      File('/tmp/1.jpg'),
    ];
    naturalSortFiles(files);
    expect(files.map((e) => e.path.split('/').last).toList(), ['1.jpg', '2.jpg', '10.jpg']);
  });
}
