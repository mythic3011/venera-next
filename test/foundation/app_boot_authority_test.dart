import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:venera/foundation/app.dart';
import 'package:venera/foundation/db/unified_comics_store.dart';

void main() {
  test('runtime component init does not open legacy runtime stores', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'app-boot-authority-',
    );
    addTearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    final store = UnifiedComicsStore(p.join(tempDir.path, 'data', 'venera.db'));
    addTearDown(store.close);

    await App.initRuntimeComponents(
      initAppData: () async {},
      initCanonicalStore: store.init,
      seedSourcePlatforms: store.seedDefaultSourcePlatforms,
    );

    expect(
      File(p.join(tempDir.path, 'data', 'venera.db')).existsSync(),
      isTrue,
    );
    expect(File(p.join(tempDir.path, 'history.db')).existsSync(), isFalse);
    expect(File(p.join(tempDir.path, 'local.db')).existsSync(), isFalse);
    expect(
      File(p.join(tempDir.path, 'local_favorite.db')).existsSync(),
      isFalse,
    );
  });
}
