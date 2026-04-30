import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera/components/components.dart';
import 'package:venera/foundation/app.dart';
import 'package:venera/foundation/appdata.dart';
import 'package:venera/foundation/debug_log_exporter.dart';
import 'package:venera/foundation/diagnostics/diagnostics.dart';
import 'package:venera/pages/settings/settings_page.dart';
import 'package:venera/utils/translations.dart';

void main() {
  final exporter = DebugLogExporter();

  setUpAll(() {
    AppTranslation.translations = {'en_US': {}};
  });

  Future<void> pumpDebugRoute(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: App.rootNavigatorKey,
        builder: (context, child) => OverlayWidget(child!),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const Material(child: DebugPage()),
                    ),
                  );
                },
                child: const Text('Open Debug'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Debug'));
    await tester.pumpAndSettle();
    expect(find.byType(DebugPage), findsOneWidget);
  }

  tearDown(() async {
    await exporter.stop();
    appdata.settings['enableDebugDiagnostics'] = false;
    DevDiagnosticsApi.debugEnabledOverride = null;
    AppDiagnostics.resetForTesting();
  });

  testWidgets('shows diagnostics console button only when enabled', (
    tester,
  ) async {
    DevDiagnosticsApi.debugEnabledOverride = true;
    await pumpDebugRoute(tester);

    expect(find.text('Open Diagnostics Console'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    DevDiagnosticsApi.debugEnabledOverride = false;

    await pumpDebugRoute(tester);

    expect(find.text('Open Diagnostics Console'), findsNothing);
    expect(find.text('Start'), findsNothing);
    expect(find.text('Disabled'), findsOneWidget);
  });

  testWidgets('desktop runtime setting enables diagnostics controls', (
    tester,
  ) async {
    DevDiagnosticsApi.debugEnabledOverride = null;
    appdata.settings['enableDebugDiagnostics'] = true;

    await pumpDebugRoute(tester);

    expect(find.text('Open Diagnostics Console'), findsOneWidget);
    expect(find.text('Start'), findsOneWidget);
    expect(find.text('Disabled'), findsNothing);
  });

  testWidgets('debug page shows merged export action and app data opener', (
    tester,
  ) async {
    await pumpDebugRoute(tester);

    expect(find.text('Open App Data Directory'), findsOneWidget);
    expect(find.text('Export Logs'), findsOneWidget);
    expect(find.text('Export Logs Snapshot'), findsNothing);
    expect(find.text('Save Logs File'), findsNothing);
  });

  testWidgets(
    'shows running toast when leaving debug page and diagnostics api is active',
    (tester) async {
      await tester.runAsync(() => exporter.start());
      await pumpDebugRoute(tester);

      await tester.pageBack();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Diagnostics API is still running'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      await tester.runAsync(() => exporter.stop());
    },
  );

  testWidgets(
    'does not show running toast when leaving debug page and diagnostics api is stopped',
    (tester) async {
      await exporter.stop();
      await pumpDebugRoute(tester);

      await tester.pageBack();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Diagnostics API is still running'), findsNothing);
    },
  );
}
