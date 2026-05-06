import 'package:venera/foundation/db/remote_comic_sync.dart';
import 'package:venera/foundation/reader/canonical_reader_pages.dart';
import 'package:venera/foundation/res.dart';

class CanonicalRemotePageProvider {
  const CanonicalRemotePageProvider({required this.canonicalReaderPages});

  final CanonicalReaderPages canonicalReaderPages;

  Future<Res<List<String>>> loadPages({
    required String sourceKey,
    required String comicId,
    required String chapterId,
  }) async {
    final canonicalComicId = canonicalRemoteComicId(
      sourceKey: sourceKey,
      comicId: comicId,
    );
    try {
      final pages = await canonicalReaderPages.loadRemotePages(
        canonicalComicId: canonicalComicId,
        chapterId: chapterId,
      );
      return Res(pages);
    } on StateError catch (e) {
      if (_isMissingCanonicalRemoteStateError(e)) {
        return const Res.error('CANONICAL_REMOTE_STATE_MISSING');
      }
      rethrow;
    }
  }

  bool _isMissingCanonicalRemoteStateError(StateError error) {
    final message = error.message;
    return message.startsWith('CANONICAL_REMOTE_COMIC_NOT_FOUND:') ||
        message.startsWith('CANONICAL_REMOTE_CHAPTER_NOT_FOUND:') ||
        message.startsWith('CANONICAL_REMOTE_PAGE_ORDER_NOT_FOUND:');
  }
}
