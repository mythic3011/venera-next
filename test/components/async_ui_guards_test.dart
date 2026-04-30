import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera/components/components.dart';
import 'package:venera/utils/translations.dart';

void main() {
  setUpAll(() {
    AppTranslation.translations = {'en_US': {}};
  });

  testWidgets('button respects initial loading state', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Button.filled(
            isLoading: true,
            onPressed: () => tapped = true,
            child: const Text('Confirm'),
          ),
        ),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.tap(find.byType(Button));
    await tester.pump();
    expect(tapped, isFalse);
  });

  testWidgets('filter chip size measurement is safe after unmount', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FilterChipFixedWidth(
            label: const Text('Tag'),
            selected: false,
            onSelected: (_) {},
          ),
        ),
      ),
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('showInputDialog confirm future can finish after dismissal', (
    tester,
  ) async {
    final key = GlobalKey<NavigatorState>();
    final completer = Completer<Object?>();

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: key,
        home: Builder(
          builder: (context) => Scaffold(
            body: Button.filled(
              onPressed: () {
                showInputDialog(
                  context: context,
                  title: 'Input',
                  onConfirm: (_) => completer.future,
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pump();
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'value');
    await tester.tap(find.text('Confirm'));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    key.currentState!.pop();
    await tester.pumpAndSettle();

    completer.complete(null);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
