import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera/foundation/comic_source/comic_source.dart';
import 'package:venera/foundation/res.dart';
import 'package:venera/pages/comic_details_page/comic_page.dart';
import 'package:venera/utils/translations.dart';

ComicDetails _buildComicDetails() {
  return ComicDetails.fromJson({
    'title': 'Test Comic',
    'subtitle': null,
    'cover': 'cover',
    'description': null,
    'tags': <String, List<String>>{},
    'chapters': null,
    'sourceKey': 'test-source',
    'comicId': 'comic-1',
    'subId': null,
    'comments': null,
  });
}

ComicSource _buildComicSource(CommentsLoader commentsLoader) {
  return ComicSource(
    'Test Source',
    'test-source',
    null,
    null,
    null,
    null,
    const [],
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    '/tmp/test_source.js',
    'https://example.com',
    '1.0.0',
    commentsLoader,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    false,
    false,
    null,
    null,
  );
}

void main() {
  setUpAll(() {
    AppTranslation.translations = {'en_US': {}};
  });

  testWidgets(
      'firstLoad error completion after dispose does not trigger setState after dispose',
      (tester) async {
    final loaderCompleter = Completer<Res<List<Comment>>>();
    final source = _buildComicSource((id, subId, page, replyTo) {
      return loaderCompleter.future;
    });

    final page = MaterialApp(
      home: CommentsPage(
        data: _buildComicDetails(),
        source: source,
      ),
    );

    await tester.pumpWidget(page);
    await tester.pump();

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pump();

    loaderCompleter.complete(const Res.error('network error'));
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}
