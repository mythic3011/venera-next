import 'package:flutter_test/flutter_test.dart';
import 'package:venera/foundation/reader/reader_page_loader.dart';
import 'package:venera/foundation/res.dart';
import 'package:venera/foundation/source_ref.dart';

void main() {
  test('loader routes local refs to local loader only', () async {
    var remoteCalled = false;
    final loader = ReaderPageLoader(
      loadLocalPages:
          ({required localType, required localComicId, chapterId}) async =>
              ['local-page'],
      loadRemotePages: ({required sourceKey, required comicId, required chapterId}) async {
        remoteCalled = true;
        return const Res(['remote-page']);
      },
      sourceExists: (_) => true,
    );

    final result = await loader.load(
      SourceRef.fromLegacyLocal(
        localType: 'local',
        localComicId: 'comic-1',
        chapterId: 'chapter-1',
      ),
    );

    expect(result.res.success, isTrue);
    expect(result.res.data, ['local-page']);
    expect(remoteCalled, isFalse);
    expect(result.loadMode, 'local');
  });

  test('loader fail-closes unknown remote source before remote loader runs', () async {
    var remoteCalled = false;
    final loader = ReaderPageLoader(
      loadLocalPages:
          ({required localType, required localComicId, chapterId}) async =>
              ['local-page'],
      loadRemotePages: ({required sourceKey, required comicId, required chapterId}) async {
        remoteCalled = true;
        return const Res(['remote-page']);
      },
      sourceExists: (_) => false,
    );

    final result = await loader.load(
      SourceRef.fromLegacyRemote(
        sourceKey: 'missing-source',
        comicId: 'comic-1',
        chapterId: 'chapter-1',
      ),
    );

    expect(result.res.error, isTrue);
    expect(result.res.errorMessage, 'SOURCE_NOT_AVAILABLE');
    expect(remoteCalled, isFalse);
    expect(result.loadMode, 'remote');
  });
}
