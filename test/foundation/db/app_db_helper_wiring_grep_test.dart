import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  int countOccurrences(String input, Pattern pattern) {
    return RegExp(pattern.toString()).allMatches(input).length;
  }

  test('db write target paths do not bypass AppDbHelper', () async {
    final files = <String>{
      'lib/foundation/appdata.dart',
      'lib/features/reader/data/reader_session_repository.dart',
      'lib/foundation/db/history_store.dart',
      'lib/foundation/db/local_comics_store.dart',
    };

    for (final path in files) {
      final content = await File(path).readAsString();
      expect(
        content,
        isNot(contains('DELETE FROM app_settings;')),
        reason: '$path must not full-delete app_settings during normal save',
      );
      if (!path.endsWith('appdata.dart')) {
        expect(
          content,
          isNot(contains('.customStatement(')),
          reason:
              '$path should not call customStatement directly for runtime writes',
        );
      }
    }
  });

  test('appdata save path is routed through AppDbHelper', () async {
    final content = await File('lib/foundation/appdata.dart').readAsString();
    expect(
      content.contains("AppDbHelper.instance.transaction('appdata.save'"),
      isTrue,
    );
    expect(content.contains('clearAppSettings('), isFalse);
  });

  test(
    'reader session repository routes writes through saveProgress/update methods',
    () async {
      final content = await File(
        'lib/features/reader/data/reader_session_repository.dart',
      ).readAsString();
      expect(
        content.contains('Future<ReaderSessionPersistResult> saveProgress('),
        isTrue,
      );
      expect(content.contains('Future<void> updateActiveTab('), isTrue);
      expect(content.contains('dbStore.saveReaderProgress('), isTrue);
    },
  );

  test(
    'source/link lane writes in unified store are routed via AppDbHelper',
    () async {
      final content = await File(
        'lib/foundation/db/unified_comics_store.dart',
      ).readAsString();

      bool hasHelperCallWithLabel(String label) {
        final pattern = RegExp(
          "AppDbHelper\\.instance\\.(?:customWrite|transaction)\\([\\s\\S]*?'$label'",
        );
        return pattern.hasMatch(content);
      }

      expect(hasHelperCallWithLabel('source.upsert_repository'), isTrue);
      expect(hasHelperCallWithLabel('source.delete_repository'), isTrue);
      expect(
        hasHelperCallWithLabel('source.replace_packages_for_repository'),
        isTrue,
      );
      expect(hasHelperCallWithLabel('source.link.upsert'), isTrue);
      expect(hasHelperCallWithLabel('source.link.upsert_chapter'), isTrue);
      expect(hasHelperCallWithLabel('source.link.upsert_page'), isTrue);
    },
  );

  test(
    'favorite-folder lane writes in unified store are routed via AppDbHelper',
    () async {
      final content = await File(
        'lib/foundation/db/unified_comics_store.dart',
      ).readAsString();

      bool hasHelperCallWithLabel(String label) {
        final pattern = RegExp(
          "AppDbHelper\\.instance\\.(?:customWrite|transaction)\\([\\s\\S]*?'$label'",
        );
        return pattern.hasMatch(content);
      }

      expect(hasHelperCallWithLabel('favorite.upsert_folder'), isTrue);
      expect(hasHelperCallWithLabel('favorite.delete_folder'), isTrue);
      expect(hasHelperCallWithLabel('favorite.rename_folder'), isTrue);
      expect(hasHelperCallWithLabel('favorite.replace_folder_order'), isTrue);
      expect(hasHelperCallWithLabel('favorite.upsert_folder_item'), isTrue);
      expect(hasHelperCallWithLabel('favorite.delete_folder_item'), isTrue);
      expect(
        hasHelperCallWithLabel('favorite.delete_folder_items_by_comic'),
        isTrue,
      );

      final laneMethods = <String>[
        'Future<void> upsertFavoriteFolder(FavoriteFolderRecord record)',
        'Future<void> deleteFavoriteFolder(String folderName)',
        'Future<void> renameFavoriteFolder({',
        'Future<void> replaceFavoriteFolderOrder(List<String> folders) async',
        'Future<void> upsertFavoriteFolderItem(FavoriteFolderItemRecord record)',
        'Future<void> deleteFavoriteFolderItem({',
        'Future<void> deleteFavoriteFolderItemsByComic(String comicId)',
      ];
      for (final method in laneMethods) {
        final start = content.indexOf(method);
        expect(start >= 0, isTrue, reason: 'method missing: $method');
        final end = content.indexOf('\n  Future<void>', start + method.length);
        final block = end == -1
            ? content.substring(start)
            : content.substring(start, end);
        expect(
          block.contains('customStatement('),
          isFalse,
          reason:
              'favorite-folder method should not call customStatement directly: $method',
        );
      }
    },
  );

  test(
    'chapter/page metadata lane writes in unified store are routed via AppDbHelper',
    () async {
      final content = await File(
        'lib/foundation/db/unified_comics_store.dart',
      ).readAsString();

      bool hasHelperCallWithLabel(String label) {
        final pattern = RegExp(
          "AppDbHelper\\.instance\\.(?:customWrite|transaction)\\([\\s\\S]*?'$label'",
        );
        return pattern.hasMatch(content);
      }

      expect(hasHelperCallWithLabel('chapter_page.upsert_chapter'), isTrue);
      expect(hasHelperCallWithLabel('chapter_page.upsert_page'), isTrue);

      final laneMethods = <String>[
        'Future<void> upsertChapter(ChapterRecord record)',
        'Future<void> upsertPage(PageRecord record)',
      ];
      for (final method in laneMethods) {
        final start = content.indexOf(method);
        expect(start >= 0, isTrue, reason: 'method missing: $method');
        final end = content.indexOf('\n  Future<void>', start + method.length);
        final block = end == -1
            ? content.substring(start)
            : content.substring(start, end);
        expect(
          block.contains('customStatement('),
          isFalse,
          reason:
              'chapter/page method should not call customStatement directly: $method',
        );
      }
    },
  );

  test(
    'page-order lane writes in unified store are routed via AppDbHelper',
    () async {
      final content = await File(
        'lib/foundation/db/unified_comics_store.dart',
      ).readAsString();

      bool hasHelperCallWithLabel(String label) {
        final pattern = RegExp(
          "AppDbHelper\\.instance\\.(?:customWrite|transaction)\\([\\s\\S]*?'$label'",
        );
        return pattern.hasMatch(content);
      }

      expect(hasHelperCallWithLabel('page_order.upsert'), isTrue);
      expect(hasHelperCallWithLabel('page_order.replace_items'), isTrue);
      expect(
        hasHelperCallWithLabel('page_order.replace_items.delete_existing'),
        isTrue,
      );
      expect(
        hasHelperCallWithLabel('page_order.replace_items.insert_item'),
        isTrue,
      );

      final laneMethods = <String>[
        'Future<void> upsertPageOrder(PageOrderRecord record)',
        'Future<void> replacePageOrderItems(',
      ];
      for (final method in laneMethods) {
        final start = content.indexOf(method);
        expect(start >= 0, isTrue, reason: 'method missing: $method');
        final end = content.indexOf('\n  Future<void>', start + method.length);
        final block = end == -1
            ? content.substring(start)
            : content.substring(start, end);
        expect(
          block.contains('customStatement('),
          isFalse,
          reason:
              'page-order method should not call customStatement directly: $method',
        );
      }
    },
  );

  test(
    'eh taxonomy lane writes in unified store are routed via AppDbHelper',
    () async {
      final content = await File(
        'lib/foundation/db/unified_comics_store.dart',
      ).readAsString();

      bool hasHelperCallWithLabel(String label) {
        final pattern = RegExp(
          "AppDbHelper\\.instance\\.(?:customWrite|transaction)\\([\\s\\S]*?'$label'",
        );
        return pattern.hasMatch(content);
      }

      expect(hasHelperCallWithLabel('tags.replace_taxonomy'), isTrue);
      expect(
        hasHelperCallWithLabel('tags.replace_taxonomy.delete_existing'),
        isTrue,
      );
      expect(
        hasHelperCallWithLabel('tags.replace_taxonomy.insert_record'),
        isTrue,
      );

      const method = 'Future<void> replaceEhTagTaxonomyRecords(';
      final start = content.indexOf(method);
      expect(start >= 0, isTrue, reason: 'method missing: $method');
      final end = content.indexOf('\n  Future<void>', start + method.length);
      final block = end == -1
          ? content.substring(start)
          : content.substring(start, end);
      expect(
        block.contains('customStatement('),
        isFalse,
        reason:
            'eh taxonomy method should not call customStatement directly: $method',
      );
    },
  );

  test(
    'cleanup/delete cascade lane writes in unified store are routed via AppDbHelper',
    () async {
      final content = await File(
        'lib/foundation/db/unified_comics_store.dart',
      ).readAsString();

      bool hasHelperCallWithLabel(String label) {
        final pattern = RegExp(
          "AppDbHelper\\.instance\\.(?:customWrite|transaction)\\([\\s\\S]*?'$label'",
        );
        return pattern.hasMatch(content);
      }

      expect(
        hasHelperCallWithLabel('cleanup.delete_comic_titles_for_comic'),
        isTrue,
      );
      expect(
        hasHelperCallWithLabel('cleanup.delete_chapters_for_comic'),
        isTrue,
      );
      expect(
        hasHelperCallWithLabel('cleanup.delete_pages_for_chapter'),
        isTrue,
      );

      final laneMethods = <String>[
        'Future<void> deleteComicTitlesForComic(String comicId)',
        'Future<void> deleteChaptersForComic(String comicId)',
        'Future<void> deletePagesForChapter(String chapterId)',
      ];
      for (final method in laneMethods) {
        final start = content.indexOf(method);
        expect(start >= 0, isTrue, reason: 'method missing: $method');
        final end = content.indexOf('\n  Future<void>', start + method.length);
        final block = end == -1
            ? content.substring(start)
            : content.substring(start, end);
        expect(
          block.contains('customStatement('),
          isFalse,
          reason:
              'cleanup/delete cascade method should not call customStatement directly: $method',
        );
      }
    },
  );

  test(
    'reader session/tab lane writes in unified store are routed via AppDbHelper',
    () async {
      final content = await File(
        'lib/foundation/db/unified_comics_store.dart',
      ).readAsString();

      bool hasHelperCallWithLabel(String label) {
        final pattern = RegExp(
          "AppDbHelper\\.instance\\.(?:customWrite|transaction)\\([\\s\\S]*?'$label'",
        );
        return pattern.hasMatch(content);
      }

      expect(hasHelperCallWithLabel('reader_sessions.upsert_tab'), isTrue);
      expect(hasHelperCallWithLabel('reader_sessions.delete_session'), isTrue);
      expect(hasHelperCallWithLabel('reader_sessions.delete_tab'), isTrue);
      expect(hasHelperCallWithLabel('reader_sessions.delete_activity'), isTrue);
      expect(hasHelperCallWithLabel('reader_sessions.clear_activity'), isTrue);

      final laneMethods = <String>[
        'Future<void> upsertReaderTab(ReaderTabRecord record)',
        'Future<void> deleteReaderSession(String sessionId)',
        'Future<void> deleteReaderTab(String tabId)',
        'Future<void> deleteReaderActivity(String comicId)',
        'Future<void> clearReaderActivity()',
      ];
      for (final method in laneMethods) {
        final start = content.indexOf(method);
        expect(start >= 0, isTrue, reason: 'method missing: $method');
        final end = content.indexOf('\n  Future<void>', start + method.length);
        final block = end == -1
            ? content.substring(start)
            : content.substring(start, end);
        expect(
          block.contains('customStatement('),
          isFalse,
          reason:
              'reader session/tab method should not call customStatement directly: $method',
        );
      }

      const upsertSessionMethod =
          'Future<void> _runReaderSessionUpsert(ReaderSessionRecord record)';
      final upsertSessionStart = content.indexOf(upsertSessionMethod);
      expect(
        upsertSessionStart >= 0,
        isTrue,
        reason: 'method missing: $upsertSessionMethod',
      );
      final upsertSessionEnd = content.indexOf(
        '\n  Future<ReaderSessionRecord?>',
        upsertSessionStart + upsertSessionMethod.length,
      );
      final upsertSessionBlock = upsertSessionEnd == -1
          ? content.substring(upsertSessionStart)
          : content.substring(upsertSessionStart, upsertSessionEnd);
      expect(upsertSessionBlock.contains('runCanonicalWrite<void>('), isTrue);
      expect(upsertSessionBlock.contains("domain: 'reader_sessions'"), isTrue);
      expect(
        upsertSessionBlock.contains("operation: 'upsert_reader_session'"),
        isTrue,
      );
    },
  );

  test(
    'remote match/import reconciliation lane writes are routed via AppDbHelper',
    () async {
      final content = await File(
        'lib/foundation/db/unified_comics_store.dart',
      ).readAsString();

      bool hasHelperCallWithLabel(String label) {
        final pattern = RegExp(
          "AppDbHelper\\.instance\\.(?:customWrite|transaction)\\([\\s\\S]*?'$label'",
        );
        return pattern.hasMatch(content);
      }

      expect(hasHelperCallWithLabel('remote_match.upsert_candidate'), isTrue);
      expect(hasHelperCallWithLabel('remote_match.delete_candidate'), isTrue);

      final laneMethods = <String>[
        'Future<void> upsertRemoteMatchCandidate(RemoteMatchCandidateRecord record)',
        'Future<void> deleteRemoteMatchCandidate(String candidateId)',
      ];
      for (final method in laneMethods) {
        final start = content.indexOf(method);
        expect(start >= 0, isTrue, reason: 'method missing: $method');
        final end = content.indexOf('\n  Future<void>', start + method.length);
        final block = end == -1
            ? content.substring(start)
            : content.substring(start, end);
        expect(
          block.contains('customStatement('),
          isFalse,
          reason:
              'remote match/import reconciliation method should not call customStatement directly: $method',
        );
      }
    },
  );

  test(
    'bulk replace methods each use exactly one AppDbHelper transaction',
    () async {
      final content = await File(
        'lib/foundation/db/unified_comics_store.dart',
      ).readAsString();

      String methodBlock(String methodSignature) {
        final start = content.indexOf(methodSignature);
        expect(start >= 0, isTrue, reason: 'method missing: $methodSignature');
        final end = content.indexOf(
          '\n  Future<void>',
          start + methodSignature.length,
        );
        return end == -1
            ? content.substring(start)
            : content.substring(start, end);
      }

      final targets = <String>[
        'Future<void> replaceSourcePackagesForRepository({',
        'Future<void> replaceFavoriteFolderOrder(List<String> folders) async',
        'Future<void> replacePageOrderItems(',
        'Future<void> replaceEhTagTaxonomyRecords(',
      ];

      for (final method in targets) {
        final block = methodBlock(method);
        final transactionCount = countOccurrences(
          block,
          r"AppDbHelper\.instance\.transaction\(",
        );
        expect(
          transactionCount,
          1,
          reason:
              'bulk replace method must keep exactly one helper transaction: $method',
        );
      }
    },
  );

  test('completed AppDbHelper lanes enforce label prefix allowlist', () async {
    final content = await File(
      'lib/foundation/db/unified_comics_store.dart',
    ).readAsString();

    String methodBlock(String methodSignature) {
      final start = content.indexOf(methodSignature);
      expect(start >= 0, isTrue, reason: 'method missing: $methodSignature');
      final end = content.indexOf(
        '\n  Future<void>',
        start + methodSignature.length,
      );
      return end == -1
          ? content.substring(start)
          : content.substring(start, end);
    }

    List<String> helperLabelsInBlock(String block) {
      final matches = RegExp(
        r"AppDbHelper\.instance\.(?:customWrite|transaction)\(\s*'([^']+)'",
      ).allMatches(block);
      return matches.map((match) => match.group(1)!).toList(growable: false);
    }

    final laneMethodPrefixes = <String, Map<String, List<String>>>{
      'source/link': {
        'prefixes': ['source.'],
        'methods': [
          'Future<void> upsertSourceRepository(SourceRepositoryRecord record)',
          'Future<void> deleteSourceRepository(String id)',
          'Future<void> replaceSourcePackagesForRepository({',
          'Future<void> upsertComicSourceLink(ComicSourceLinkRecord record) async',
          'Future<void> upsertChapterSourceLink(ChapterSourceLinkRecord record)',
          'Future<void> upsertPageSourceLink(PageSourceLinkRecord record)',
        ],
      },
      'favorite-folder': {
        'prefixes': ['favorite.'],
        'methods': [
          'Future<void> upsertFavoriteFolder(FavoriteFolderRecord record)',
          'Future<void> deleteFavoriteFolder(String folderName)',
          'Future<void> renameFavoriteFolder({',
          'Future<void> replaceFavoriteFolderOrder(List<String> folders) async',
          'Future<void> upsertFavoriteFolderItem(FavoriteFolderItemRecord record)',
          'Future<void> deleteFavoriteFolderItem({',
          'Future<void> deleteFavoriteFolderItemsByComic(String comicId)',
        ],
      },
      'page-order': {
        'prefixes': ['page_order.'],
        'methods': [
          'Future<void> upsertPageOrder(PageOrderRecord record)',
          'Future<void> replacePageOrderItems(',
        ],
      },
      'chapter/page metadata': {
        'prefixes': ['chapter_page.'],
        'methods': [
          'Future<void> upsertChapter(ChapterRecord record)',
          'Future<void> upsertPage(PageRecord record)',
        ],
      },
      'eh taxonomy': {
        'prefixes': ['tags.'],
        'methods': ['Future<void> replaceEhTagTaxonomyRecords('],
      },
      'cleanup/delete cascade': {
        'prefixes': ['cleanup.'],
        'methods': [
          'Future<void> deleteComicTitlesForComic(String comicId)',
          'Future<void> deleteChaptersForComic(String comicId)',
          'Future<void> deletePagesForChapter(String chapterId)',
        ],
      },
      'reader session/tab': {
        'prefixes': ['reader_sessions.'],
        'methods': [
          'Future<void> upsertReaderTab(ReaderTabRecord record)',
          'Future<void> deleteReaderSession(String sessionId)',
          'Future<void> deleteReaderTab(String tabId)',
          'Future<void> deleteReaderActivity(String comicId)',
          'Future<void> clearReaderActivity()',
          'Future<ReaderSessionPersistResult> saveReaderProgress({',
        ],
      },
      'remote match/import reconciliation': {
        'prefixes': ['remote_match.'],
        'methods': [
          'Future<void> upsertRemoteMatchCandidate(RemoteMatchCandidateRecord record)',
          'Future<void> deleteRemoteMatchCandidate(String candidateId)',
        ],
      },
      'miscellaneous legacy writes': {
        'prefixes': [
          'cache.',
          'settings_kv.',
          'search_history.',
          'implicit_data.',
          'history_event.',
        ],
        'methods': [
          'Future<void> upsertCacheEntry(CacheEntryRecord record)',
          'Future<void> deleteCacheEntry(String cacheKey)',
          'Future<void> deleteAllCacheEntries()',
          'Future<void> touchCacheEntryAccess({',
          'Future<void> upsertAppSetting(AppSettingRecord record)',
          'Future<void> clearAppSettings()',
          'Future<void> upsertSearchHistory(SearchHistoryRecord record)',
          'Future<void> clearSearchHistory()',
          'Future<void> upsertImplicitData(ImplicitDataRecord record)',
          'Future<void> clearImplicitData()',
          'Future<void> upsertHistoryEvent(HistoryEventRecord record)',
        ],
      },
    };

    for (final lane in laneMethodPrefixes.entries) {
      final prefixes = lane.value['prefixes']!;
      final methods = lane.value['methods']!;
      for (final method in methods) {
        final block = methodBlock(method);
        final labels = helperLabelsInBlock(block);
        expect(
          labels,
          isNotEmpty,
          reason: 'no helper labels found in: $method',
        );
        for (final label in labels) {
          final allowed = prefixes.any(label.startsWith);
          expect(
            allowed,
            isTrue,
            reason:
                'label "$label" in ${lane.key} lane must start with one of: ${prefixes.join(', ')} (method: $method)',
          );
        }
      }
    }
  });

  test(
    'comic metadata/library item lane writes in unified store are routed via AppDbHelper',
    () async {
      final content = await File(
        'lib/foundation/db/unified_comics_store.dart',
      ).readAsString();

      bool hasHelperCallWithLabel(String label) {
        final pattern = RegExp(
          "AppDbHelper\\.instance\\.(?:customWrite|transaction)\\([\\s\\S]*?'$label'",
        );
        return pattern.hasMatch(content);
      }

      expect(hasHelperCallWithLabel('comic_library.upsert_comic'), isTrue);
      expect(
        hasHelperCallWithLabel('comic_library.insert_comic_title'),
        isTrue,
      );
      expect(hasHelperCallWithLabel('comic_library.upsert_favorite'), isTrue);
      expect(hasHelperCallWithLabel('comic_library.delete_favorite'), isTrue);
      expect(
        hasHelperCallWithLabel('comic_library.upsert_local_library_item'),
        isTrue,
      );
      expect(
        hasHelperCallWithLabel('comic_library.delete_local_library_item_by_id'),
        isTrue,
      );
      expect(hasHelperCallWithLabel('comic_library.upsert_user_tag'), isTrue);
      expect(
        hasHelperCallWithLabel('comic_library.attach_user_tag_to_comic'),
        isTrue,
      );
      expect(
        hasHelperCallWithLabel('comic_library.remove_user_tag_from_comic'),
        isTrue,
      );

      final laneMethods = <String>[
        'Future<void> upsertComic(ComicRecord record)',
        'Future<void> insertComicTitle(ComicTitleRecord record)',
        'Future<void> upsertFavorite(FavoriteRecord record)',
        'Future<void> deleteFavorite(String comicId)',
        'Future<void> upsertLocalLibraryItem(LocalLibraryItemRecord record)',
        'Future<void> deleteLocalLibraryItemById(String localLibraryItemId)',
        'Future<void> upsertUserTag(UserTagRecord record)',
        'Future<void> attachUserTagToComic(ComicUserTagRecord record)',
        'Future<void> removeUserTagFromComic({',
      ];
      for (final method in laneMethods) {
        final start = content.indexOf(method);
        expect(start >= 0, isTrue, reason: 'method missing: $method');
        final end = content.indexOf('\n  Future<void>', start + method.length);
        final block = end == -1
            ? content.substring(start)
            : content.substring(start, end);
        expect(
          block.contains('customStatement('),
          isFalse,
          reason:
              'comic metadata/library item method should not call customStatement directly: $method',
        );
      }
    },
  );

  test(
    'misc lane writes in unified store are routed via AppDbHelper with scoped prefixes',
    () async {
      final content = await File(
        'lib/foundation/db/unified_comics_store.dart',
      ).readAsString();

      bool hasHelperCallWithLabel(String label) {
        final pattern = RegExp(
          "AppDbHelper\\.instance\\.(?:customWrite|transaction)\\([\\s\\S]*?'$label'",
        );
        return pattern.hasMatch(content);
      }

      expect(hasHelperCallWithLabel('cache.upsert_entry'), isTrue);
      expect(hasHelperCallWithLabel('cache.delete_entry'), isTrue);
      expect(hasHelperCallWithLabel('cache.delete_all_entries'), isTrue);
      expect(hasHelperCallWithLabel('cache.touch_entry_access'), isTrue);
      expect(hasHelperCallWithLabel('settings_kv.upsert_setting'), isTrue);
      expect(hasHelperCallWithLabel('settings_kv.clear_settings'), isTrue);
      expect(hasHelperCallWithLabel('search_history.upsert_keyword'), isTrue);
      expect(hasHelperCallWithLabel('search_history.clear'), isTrue);
      expect(hasHelperCallWithLabel('implicit_data.upsert'), isTrue);
      expect(hasHelperCallWithLabel('implicit_data.clear'), isTrue);
      expect(hasHelperCallWithLabel('history_event.upsert'), isTrue);

      final laneMethods = <String>[
        'Future<void> upsertCacheEntry(CacheEntryRecord record)',
        'Future<void> deleteCacheEntry(String cacheKey)',
        'Future<void> deleteAllCacheEntries()',
        'Future<void> touchCacheEntryAccess({',
        'Future<void> upsertAppSetting(AppSettingRecord record)',
        'Future<void> clearAppSettings()',
        'Future<void> upsertSearchHistory(SearchHistoryRecord record)',
        'Future<void> clearSearchHistory()',
        'Future<void> upsertImplicitData(ImplicitDataRecord record)',
        'Future<void> clearImplicitData()',
        'Future<void> upsertHistoryEvent(HistoryEventRecord record)',
      ];
      for (final method in laneMethods) {
        final start = content.indexOf(method);
        expect(start >= 0, isTrue, reason: 'method missing: $method');
        final end = content.indexOf('\n  Future<void>', start + method.length);
        final block = end == -1
            ? content.substring(start)
            : content.substring(start, end);
        expect(
          block.contains('customStatement('),
          isFalse,
          reason:
              'misc lane method should not call customStatement directly: $method',
        );
      }
    },
  );

  test(
    'unified store blocks direct runtime transaction/customStatement bypasses',
    () async {
      final content = await File(
        'lib/foundation/db/unified_comics_store.dart',
      ).readAsString();

      final transactionMatches = RegExp(
        r'(?<!AppDbHelper\.instance)\.transaction\(',
      ).allMatches(content);
      expect(
        transactionMatches,
        isEmpty,
        reason:
            'direct .transaction(...) is only allowed as AppDbHelper.instance.transaction(...)',
      );

      final customStatementLines = content
          .split('\n')
          .where((line) => line.contains('customStatement('))
          .map((line) => line.trim())
          .toList(growable: false);

      expect(
        customStatementLines,
        equals(<String>[
          "await customStatement('PRAGMA foreign_keys = ON;');",
          "await customStatement('PRAGMA journal_mode = WAL;');",
          "await customStatement('PRAGMA busy_timeout = 5000;');",
          'await customStatement(',
          'await customStatement(',
          'action: () => customStatement(',
        ]),
        reason:
            'customStatement(...) in unified store must stay limited to setup PRAGMA and helper-controlled inner SQL blocks',
      );
    },
  );

  test('all unified store runtime helper labels use approved prefixes', () async {
    final content = await File(
      'lib/foundation/db/unified_comics_store.dart',
    ).readAsString();

    final allowedPrefixes = <String>[
      'source.',
      'favorite.',
      'page_order.',
      'tags.',
      'cleanup.',
      'reader_sessions.',
      'chapter_page.',
      'remote_match.',
      'comic_library.',
      'cache.',
      'settings_kv.',
      'search_history.',
      'implicit_data.',
      'history_event.',
    ];

    final helperLabelMatches = RegExp(
      r"AppDbHelper\.instance\.(?:customWrite|transaction)\(\s*'([^']+)'",
    ).allMatches(content);
    final labels = helperLabelMatches
        .map((match) => match.group(1)!)
        .toList(growable: false);

    expect(labels, isNotEmpty, reason: 'no AppDbHelper labels found');
    for (final label in labels) {
      final allowed = allowedPrefixes.any(label.startsWith);
      expect(
        allowed,
        isTrue,
        reason:
            'label "$label" must start with an approved prefix: ${allowedPrefixes.join(', ')}',
      );
    }
  });
}
