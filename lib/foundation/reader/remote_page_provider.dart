import 'package:venera/foundation/reader/page_provider.dart';
import 'package:venera/foundation/res.dart';
import 'package:venera/foundation/source_ref.dart';

typedef RemotePagesLoader = Future<Res<List<String>>> Function({
  required String sourceKey,
  required String comicId,
  required String chapterId,
});

class RemotePageProvider implements ReadablePageProvider {
  const RemotePageProvider({required this.loadRemotePages});

  final RemotePagesLoader loadRemotePages;

  @override
  Future<Res<List<String>>> loadPages(SourceRef ref) async {
    if (ref.type != SourceRefType.remote) {
      return const Res.error('SOURCE_REF_TYPE_MISMATCH');
    }

    final comicId = ref.params['comicId'] as String?;
    final chapterId = ref.params['chapterId'] as String?;

    if (comicId == null || chapterId == null) {
      return const Res.error('SOURCE_REF_NOT_FOUND');
    }

    return loadRemotePages(
      sourceKey: ref.sourceKey,
      comicId: comicId,
      chapterId: chapterId,
    );
  }
}
