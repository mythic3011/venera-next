import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera/foundation/local_storage_legacy_bridge.dart';
import 'package:venera/pages/settings/settings_page.dart';

class _LatePathHolder {
  late final String path;
}

void main() {
  testWidgets(
    'settings page does not crash when local comics path is uninitialized',
    (tester) async {
      final holder = _LatePathHolder();
      final safePath = tryReadLocalComicsStoragePath(reader: () => holder.path);
      final displayPath = formatLocalComicsStoragePathForDisplay(safePath);

      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: Text(displayPath))),
      );

      expect(find.text('Not configured'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

