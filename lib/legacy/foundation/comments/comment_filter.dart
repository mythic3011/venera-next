import 'package:venera/foundation/appdata.dart';
import 'package:venera/features/sources/comic_source/comic_source.dart';

class CommentFilter {
  const CommentFilter(this.blockedWords);

  final List<String> blockedWords;

  factory CommentFilter.fromSettings() {
    final raw = appdata.settings['blockedCommentWords'];
    if (raw is! List) {
      return const CommentFilter(<String>[]);
    }
    return CommentFilter(raw.map((e) => e.toString()).toList());
  }

  bool shouldBlock(Comment comment) {
    if (blockedWords.isEmpty) return false;
    final content = comment.content.toLowerCase();
    for (final word in blockedWords) {
      if (content.contains(word.toLowerCase())) {
        return true;
      }
    }
    return false;
  }

  List<Comment> filterComments(Iterable<Comment> comments) {
    return comments.where((c) => !shouldBlock(c)).toList();
  }
}
