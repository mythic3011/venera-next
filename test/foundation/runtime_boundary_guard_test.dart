import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test(
    'runtime authority guard: selected runtime files avoid LocalManager direct calls',
    () async {
      final base = Directory.current.path;
      final guardedFiles = <String>[
        p.join(base, 'lib', 'pages', 'local_comics_page.dart'),
        p.join(base, 'lib', 'pages', 'settings', 'app.dart'),
        p.join(base, 'lib', 'pages', 'comic_details_page', 'comic_page.dart'),
        p.join(base, 'lib', 'pages', 'comic_details_page', 'actions.dart'),
        p.join(
          base,
          'lib',
          'foundation',
          'image_provider',
          'cached_image.dart',
        ),
        p.join(
          base,
          'lib',
          'foundation',
          'image_provider',
          'history_image_provider.dart',
        ),
        p.join(
          base,
          'lib',
          'foundation',
          'image_provider',
          'image_favorites_provider.dart',
        ),
        p.join(base, 'lib', 'pages', 'home_page.dart'),
        p.join(base, 'lib', 'pages', 'home_page_legacy_sections.dart'),
        p.join(base, 'lib', 'pages', 'favorites', 'local_favorites_page.dart'),
        p.join(base, 'lib', 'foundation', 'favorites.dart'),
      ];

      for (final filePath in guardedFiles) {
        final content = await File(filePath).readAsString();
        expect(content.contains('LocalManager('), isFalse, reason: filePath);
      }
    },
  );
}
