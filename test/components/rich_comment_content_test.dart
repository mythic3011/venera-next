import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera/components/rich_comment_content.dart';

void main() {
  testWidgets('rich comment updates text when widget text changes', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: RichCommentContent(text: 'hello')),
      ),
    );
    expect(find.text('hello'), findsOneWidget);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: RichCommentContent(text: 'updated')),
      ),
    );
    await tester.pump();
    expect(find.text('updated'), findsOneWidget);
    expect(find.text('hello'), findsNothing);
  });

  testWidgets('rich comment updates auto-link and image list on text change', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: RichCommentContent(
            text: 'visit https://example.com',
            showImages: true,
          ),
        ),
      ),
    );
    expect(find.byType(SelectableText), findsOneWidget);
    expect(find.byType(Image), findsNothing);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: RichCommentContent(
            text:
                '<a href="https://example.com/open"><img src="https://example.com/cover.png"></a>',
            showImages: true,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('rich comment unmounts cleanly after link rendering', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: RichCommentContent(
            text: '<a href="https://example.com">open</a>',
          ),
        ),
      ),
    );
    expect(find.text('open'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
