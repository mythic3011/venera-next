import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('global context callsites are fully classified', () {
    const classifiedByFile = <String, String>{
      'lib/main.dart': 'allowed_bootstrap',
      'lib/foundation/local/local_comic.dart': 'background_service',
      'lib/init.dart': 'background_service',
      'lib/network/cloudflare.dart': 'background_service',
      'lib/utils/data_sync.dart': 'background_service',
    };
    const migrationOwnerByFile = <String, String>{
      'lib/foundation/local/local_comic.dart': 'local-foundation',
      'lib/init.dart': 'bootstrap',
      'lib/network/cloudflare.dart': 'network',
      'lib/utils/data_sync.dart': 'data-sync',
    };
    const migrationNoteByFile = <String, String>{
      'lib/foundation/local/local_comic.dart':
          'Emit typed result/events and let UI layer own dialog/navigation rendering.',
      'lib/init.dart':
          'Move startup update prompt dispatch to UI lifecycle owner instead of init global context.',
      'lib/network/cloudflare.dart':
          'Stop direct UI on network layer; emit diagnostics + typed status only.',
      'lib/utils/data_sync.dart':
          'Return sync result to UI layer; avoid global context resolution in utility layer.',
    };

    final rg = Process.runSync(
      'rg',
      [
        '-n',
        r'App\.rootContext|App\.rootNavigatorKey\.currentContext|App\.mainNavigatorKey\?\.currentContext',
        'lib',
      ],
      runInShell: false,
    );

    expect(rg.exitCode, 0, reason: 'rg failed: ${rg.stderr}');

    final stdout = (rg.stdout as String).trim();
    final foundFiles = <String>{};
    if (stdout.isNotEmpty) {
      for (final line in stdout.split('\n')) {
        final firstColon = line.indexOf(':');
        if (firstColon <= 0) {
          continue;
        }
        foundFiles.add(line.substring(0, firstColon));
      }
    }

    final missingClassification = foundFiles.where((f) => !classifiedByFile.containsKey(f)).toList()
      ..sort();
    final staleClassification = classifiedByFile.keys.where((f) => !foundFiles.contains(f)).toList()..sort();

    expect(
      missingClassification,
      isEmpty,
      reason:
          'New global-context file(s) must be classified first:\n${missingClassification.join('\n')}',
    );

    expect(
      staleClassification,
      isEmpty,
      reason:
          'Classification map contains stale file(s):\n${staleClassification.join('\n')}',
    );

    final invalidCategory = <String>[];
    const validCategories = <String>{
      'allowed_bootstrap',
      'allowed_emergency',
      'ui_navigation',
      'ui_message',
      'dialog_popup',
      'background_service',
      'unknown',
    };

    for (final entry in classifiedByFile.entries) {
      if (!validCategories.contains(entry.value)) {
        invalidCategory.add('${entry.key} -> ${entry.value}');
      }
    }

    expect(
      invalidCategory,
      isEmpty,
      reason: 'Invalid App.rootContext category values:\n${invalidCategory.join('\n')}',
    );

    final missingDebtMetadata = <String>[];
    const alwaysAllowed = <String>{'allowed_bootstrap', 'allowed_emergency'};
    for (final entry in classifiedByFile.entries) {
      if (alwaysAllowed.contains(entry.value)) {
        continue;
      }
      final owner = migrationOwnerByFile[entry.key];
      final note = migrationNoteByFile[entry.key];
      if (owner == null || owner.trim().isEmpty || note == null || note.trim().isEmpty) {
        missingDebtMetadata.add(entry.key);
      }
    }
    expect(
      missingDebtMetadata,
      isEmpty,
      reason:
          'Non-allowed App.rootContext usage must have owner+migration note:\n${missingDebtMetadata.join('\n')}',
    );
  });
}
