import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:venera/foundation/db/unified_comics_store.dart';
import 'package:venera/utils/tags_translation.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late UnifiedComicsStore store;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('venera-tags-translation-');
    store = UnifiedComicsStore('${tempDir.path}/data/venera.db');
    await store.init();
    TagsTranslation.resetStateForTest();
  });

  tearDown(() async {
    TagsTranslation.resetStateForTest();
    await store.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test(
    'readData preloads EH taxonomy from DB without network refresh',
    () async {
      var downloadCalls = 0;
      TagsTranslation.setDownloaderForTest(() async {
        downloadCalls += 1;
        return '';
      });
      await store.replaceEhTagTaxonomyRecords('ehentai', const [
        EhTagTaxonomyRecord(
          providerKey: 'ehentai',
          locale: 'zh_CN',
          namespace: 'female',
          tagKey: 'glasses',
          translatedLabel: '眼镜',
          sourceSha: 'db-sha',
          sourceVersion: 7,
        ),
      ]);

      await TagsTranslation.readData(store: store);

      expect(downloadCalls, 0);
      expect(
        TagsTranslation.translationTagWithNamespace('glasses', 'female'),
        '眼镜',
      );
    },
  );

  test(
    'explicit EH refresh writes DB, reloads sync map, and skips unchanged SHA',
    () async {
      const payload = '''
{"version":7,"head":{"sha":"sha-123"},"data":[{"namespace":"female","data":{"glasses":{"name":"眼镜"}}}]}
''';

      final updated = await TagsTranslation.refreshEhTaxonomy(
        store: store,
        downloader: () async => payload,
      );
      final skipped = await TagsTranslation.refreshEhTaxonomy(
        store: store,
        downloader: () async => payload,
      );
      final taxonomy = await store.loadEhTagTaxonomy(
        providerKey: 'ehentai',
        locale: 'zh_CN',
      );

      expect(updated, isTrue);
      expect(skipped, isFalse);
      expect(taxonomy.single.sourceSha, 'sha-123');
      expect(
        TagsTranslation.translationTagWithNamespace('glasses', 'female'),
        '眼镜',
      );
    },
  );
}
