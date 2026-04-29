import 'package:flutter_test/flutter_test.dart';
import 'package:venera/foundation/comic_type.dart';
import 'package:venera/foundation/history.dart';
import 'package:venera/pages/comic_details_page/comic_page.dart';

class _TestHistoryModel with HistoryMixin {
  @override
  final String title = 'Test Comic';

  @override
  final String? subTitle = null;

  @override
  final String cover = 'cover';

  @override
  final String id = 'comic-1';

  @override
  final HistoryType historyType = ComicType.local;
}

void main() {
  test('normal chapter readEpisode string marks chapter as visited', () {
    final history = History.fromModel(
      model: _TestHistoryModel(),
      ep: 1,
      page: 1,
      readChapters: {'1'},
    );

    expect(comicChapterIsVisited(history, rawIndex: '1'), isTrue);
    expect(comicChapterIsVisited(history, rawIndex: '2'), isFalse);
  });
}
