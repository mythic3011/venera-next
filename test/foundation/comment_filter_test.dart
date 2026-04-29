import 'package:flutter_test/flutter_test.dart';
import 'package:venera/foundation/comic_source/comic_source.dart';
import 'package:venera/foundation/comments/comment_filter.dart';

Comment _comment(String content) {
  return Comment.fromJson({
    'userName': 'tester',
    'avatar': null,
    'content': content,
    'time': null,
    'replyCount': null,
    'id': '1',
    'score': null,
    'isLiked': null,
    'voteStatus': null,
  });
}

void main() {
  test('blocks comments by case-insensitive substring match', () {
    final filter = CommentFilter(['Spoiler']);

    expect(filter.shouldBlock(_comment('contains spoiler text')), isTrue);
    expect(filter.shouldBlock(_comment('safe text')), isFalse);
  });

  test('filters blocked comments while preserving order', () {
    final filter = CommentFilter(['bad']);
    final comments = [
      _comment('first'),
      _comment('bad middle'),
      _comment('last'),
    ];

    expect(
      filter.filterComments(comments).map((comment) => comment.content),
      ['first', 'last'],
    );
  });
}
