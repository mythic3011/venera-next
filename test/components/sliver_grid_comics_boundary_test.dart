import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('SliverGridComics uses reader status repository authority path', () {
    final file = File('lib/components/comic.dart');
    final content = file.readAsStringSync();

    expect(content.contains('App.unifiedComicsStore'), isFalse);
    expect(
      RegExp(
        r'App\.repositories\.readerStatus\s*\.\s*loadStatusesForComics',
      ).hasMatch(content),
      isTrue,
    );
  });
}
