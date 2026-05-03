import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('App.rootContext callsites are fully classified', () {
    const classifiedByFile = <String, String>{
      'lib/main.dart': 'allowed_bootstrap',
    };
    const migrationOwnerByFile = <String, String>{};
    const migrationNoteByFile = <String, String>{};

    final rg = Process.runSync(
      'rg',
      ['-n', r'App\.rootContext', 'lib'],
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
          'New App.rootContext file(s) must be classified first:\n${missingClassification.join('\n')}',
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
