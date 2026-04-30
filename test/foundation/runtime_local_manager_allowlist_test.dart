import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('LocalManager usage stays inside allowlisted authority files', () async {
    final libRoot = Directory(p.join(Directory.current.path, 'lib'));
    final allowedSuffixes = <String>{
      p.join('foundation', 'local.dart'),
      p.join('foundation', 'local', 'local_comic.dart'),
      p.join('foundation', 'comic_detail_legacy_bridge.dart'),
      p.join('foundation', 'download_queue_legacy_bridge.dart'),
      p.join('foundation', 'local_comics_legacy_bridge.dart'),
      p.join('foundation', 'local_storage_legacy_bridge.dart'),
    };

    final violations = <String>[];
    await for (final entity in libRoot.list(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) {
        continue;
      }
      final content = await entity.readAsString();
      if (!content.contains('LocalManager(')) {
        continue;
      }
      final normalizedPath = p.normalize(entity.path);
      final relative = p.relative(normalizedPath, from: libRoot.path);
      final isAllowed = allowedSuffixes.contains(relative);
      if (!isAllowed) {
        violations.add(relative);
      }
    }

    expect(
      violations,
      isEmpty,
      reason: 'Unexpected LocalManager runtime callsites: $violations',
    );
  });
}
