import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:venera/foundation/app.dart';
import 'package:venera/utils/data.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempRoot;
  late Directory dataDir;
  late Directory cacheDir;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('venera-data-import-');
    dataDir = Directory('${tempRoot.path}/data')..createSync(recursive: true);
    cacheDir = Directory('${tempRoot.path}/cache')..createSync(recursive: true);
    App.dataPath = dataDir.path;
    App.cachePath = cacheDir.path;
    setArchiveExtractorForTest((_, outputDir) async {
      final out = Directory(outputDir)..createSync(recursive: true);
      File('${out.path}/history.db').writeAsStringSync('legacy-history');
      File(
        '${out.path}/local_favorite.db',
      ).writeAsStringSync('legacy-favorites');
    });
  });

  tearDown(() async {
    setArchiveExtractorForTest(null);
    if (tempRoot.existsSync()) {
      await tempRoot.delete(recursive: true);
    }
  });

  test(
    'importAppData ignores legacy runtime db files and does not restore them',
    () async {
      final input = File('${tempRoot.path}/fixture.venera')
        ..writeAsStringSync('fixture');

      await importAppData(input);

      expect(File('${App.dataPath}/history.db').existsSync(), isFalse);
      expect(File('${App.dataPath}/local_favorite.db').existsSync(), isFalse);
    },
  );
}
