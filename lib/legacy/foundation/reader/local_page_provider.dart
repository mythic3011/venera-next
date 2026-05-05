import 'package:venera/foundation/reader/page_provider.dart';
import 'package:venera/foundation/res.dart';
import 'package:venera/foundation/sources/source_ref.dart';

typedef LocalPagesLoader = Future<List<String>> Function({
  required String localType,
  required String localComicId,
  String? chapterId,
});

class LocalPageProvider implements ReadablePageProvider {
  const LocalPageProvider({required this.loadLocalPages});

  final LocalPagesLoader loadLocalPages;

  @override
  Future<Res<List<String>>> loadPages(SourceRef ref) async {
    if (ref.type != SourceRefType.local) {
      return const Res.error('SOURCE_REF_TYPE_MISMATCH');
    }

    final localType = ref.params['localType'] as String?;
    final localComicId = ref.params['localComicId'] as String?;
    final chapterId = ref.params['chapterId'] as String?;

    if (localType == null || localComicId == null) {
      return const Res.error('SOURCE_REF_NOT_FOUND');
    }

    try {
      final pages = await loadLocalPages(
        localType: localType,
        localComicId: localComicId,
        chapterId: chapterId,
      );
      return Res(pages);
    } catch (_) {
      return const Res.error('LOCAL_ASSET_MISSING');
    }
  }
}
