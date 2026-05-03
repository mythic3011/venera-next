import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('lib/utils stays helper-only outside quarantine', () {
    const quarantinedFiles = <String>{
      // Temporary quarantine for existing mixed files. Follow-up slices should
      // move these files out of lib/utils and then remove them from this set.
      'data_sync.dart',
      'data.dart',
      'import_comic.dart',
      'cbz.dart',
      'epub.dart',
      'pdf.dart',
      'io.dart',
      'translations.dart',
      'tags_translation.dart',
      'local_import_storage.dart',
    };

    final forbiddenImportPatterns = <RegExp>[
      RegExp(r'^package:venera/pages/'),
      RegExp(r'^package:venera/components/'),
      RegExp(r'^package:venera/foundation/(appdata|favorites|history|local)\.dart$'),
      RegExp(r'^\.\./pages/'),
      RegExp(r'^\.\./components/'),
    ];

    final utilsDir = Directory('lib/utils');
    expect(utilsDir.existsSync(), isTrue, reason: 'Expected lib/utils to exist');

    final importRegex = RegExp(r'''^\s*import\s+['"]([^'"]+)['"]''', multiLine: true);
    final violations = <String>[];

    for (final entity in utilsDir.listSync()) {
      if (entity is! File || !entity.path.endsWith('.dart')) {
        continue;
      }
      final fileName = entity.uri.pathSegments.last;
      if (quarantinedFiles.contains(fileName)) {
        continue;
      }

      final contents = entity.readAsStringSync();
      final matches = importRegex.allMatches(contents);
      for (final match in matches) {
        final importPath = match.group(1)!;
        final isForbidden = forbiddenImportPatterns.any((pattern) => pattern.hasMatch(importPath));
        if (isForbidden) {
          violations.add('lib/utils/$fileName -> $importPath');
        }
      }
    }

    expect(
      violations,
      isEmpty,
      reason: 'Non-quarantined utils file imported forbidden dependency:\n${violations.join('\n')}',
    );
  });
}
