import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera/components/components.dart';

void main() {
  testWidgets(
    'TabViewBody detaches old controller listener on controller swap',
    (tester) async {
      final oldController = TabController(length: 2, vsync: tester);
      final newController = TabController(length: 2, vsync: tester);

      TabController active = oldController;

      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              return Column(
                children: [
                  ElevatedButton(
                    onPressed: () => setState(() => active = newController),
                    child: const Text('swap'),
                  ),
                  Expanded(
                    child: TabViewBody(
                      controller: active,
                      children: const [Text('old'), Text('new')],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      );

      oldController.index = 1;
      await tester.pump();
      expect(find.text('new'), findsOneWidget);

      await tester.tap(find.text('swap'));
      await tester.pump();

      newController.index = 0;
      await tester.pump();
      expect(find.text('old'), findsOneWidget);

      oldController.index = 0;
      await tester.pump();
      expect(find.text('old'), findsOneWidget);

      oldController.dispose();
      newController.dispose();
    },
  );
}
