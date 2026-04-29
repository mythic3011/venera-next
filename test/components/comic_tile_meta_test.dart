import 'package:flutter_test/flutter_test.dart';
import 'package:venera/components/components.dart';
import 'package:venera/foundation/comic_type.dart';
import 'package:venera/foundation/history.dart';

void main() {
  test('ComicTileMeta normalizes zero history page outside build', () {
    final history = History.fromMap({
      'type': ComicType.local.value,
      'time': DateTime(2026).millisecondsSinceEpoch,
      'title': 'Title',
      'subtitle': '',
      'cover': '',
      'ep': 1,
      'page': 0,
      'id': 'comic-1',
      'readEpisode': const <String>[],
      'max_page': 10,
    });

    final meta = ComicTileMeta.fromStatus(
      isFavorite: true,
      history: history,
      displayMode: 'brief',
    );

    expect(meta.isFavorite, isTrue);
    expect(meta.history?.page, 1);
    expect(history.page, 0);
  });
}
