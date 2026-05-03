import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('legacy manager usage stays inside allowlisted authority files', () async {
    final libRoot = Directory(p.join(Directory.current.path, 'lib'));
    final allowlistByToken = <String, Set<String>>{
      'LocalManager(': <String>{
        p.join('foundation', 'local.dart'),
        p.join('foundation', 'local', 'local_comic.dart'),
        p.join('foundation', 'comic_detail_legacy_bridge.dart'),
        p.join('foundation', 'download_queue_legacy_bridge.dart'),
        p.join('foundation', 'local_comics_legacy_bridge.dart'),
        p.join('foundation', 'local_storage_legacy_bridge.dart'),
      },
      'LocalFavoritesManager(': <String>{
        p.join('foundation', 'favorites.dart'),
        p.join('foundation', 'follow_updates.dart'),
        p.join('foundation', 'local.dart'),
        p.join('foundation', 'history.dart'),
        p.join('foundation', 'comic_detail_legacy_bridge.dart'),
        p.join('features', 'favorites', 'data', 'favorites_runtime_repository.dart'),
        p.join('foundation', 'favorite_runtime_authority.dart'),
        p.join('headless.dart'),
        p.join('utils', 'data.dart'),
        p.join('utils', 'data_sync.dart'),
        p.join('utils', 'import_comic.dart'),
        p.join('pages', 'follow_updates_page.dart'),
        p.join('pages', 'favorites', 'local_favorites_page.dart'),
        p.join('pages', 'settings', 'local_favorites.dart'),
        p.join('pages', 'home_page_legacy_sections.dart'),
      },
      'HistoryManager(': <String>{
        p.join('foundation', 'history.dart'),
        p.join('foundation', 'local.dart'),
        p.join('foundation', 'local', 'local_comic.dart'),
        p.join('foundation', 'image_favorites.dart'),
        p.join('foundation', 'image_provider', 'history_image_provider.dart'),
        p.join('pages', 'home_page.dart'),
        p.join('pages', 'comic_details_page', 'actions.dart'),
        p.join('features', 'reader', 'presentation', 'loading.dart'),
        p.join('utils', 'data.dart'),
      },
    };

    final violations = <String>[];
    await for (final entity in libRoot.list(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) {
        continue;
      }
      final content = await entity.readAsString();
      final normalizedPath = p.normalize(entity.path);
      final relative = p.relative(normalizedPath, from: libRoot.path);
      for (final entry in allowlistByToken.entries) {
        if (!content.contains(entry.key)) {
          continue;
        }
        final isAllowed = entry.value.contains(relative);
        if (!isAllowed) {
          violations.add('${entry.key} -> $relative');
        }
      }
    }

    expect(
      violations,
      isEmpty,
      reason: 'Unexpected LocalManager runtime callsites: $violations',
    );
  });
}
