import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera/components/components.dart';
import 'package:venera/foundation/diagnostics/diagnostics.dart' as app_diag;
import 'package:venera/foundation/res.dart';

class _SequencedLoadWidget extends StatefulWidget {
  const _SequencedLoadWidget({
    required this.steps,
    required this.stepSignals,
    required this.stateKey,
  }) : super(key: stateKey);

  final List<Res<String>> steps;
  final List<Completer<void>> stepSignals;
  final GlobalKey<_SequencedLoadWidgetState> stateKey;

  @override
  State<_SequencedLoadWidget> createState() => _SequencedLoadWidgetState();
}

class _SequencedLoadWidgetState
    extends LoadingState<_SequencedLoadWidget, String> {
  int _index = 0;

  @override
  Future<Res<String>> loadData() async {
    final i = _index++;
    await widget.stepSignals[i].future;
    return widget.steps[i];
  }

  @override
  Widget buildContent(BuildContext context, String data) => Text(data);
}

class _MultiPageProbeWidget extends StatefulWidget {
  const _MultiPageProbeWidget({required this.stateKey, required this.responses})
    : super(key: stateKey);

  final GlobalKey<_MultiPageProbeWidgetState> stateKey;
  final Map<int, Res<List<int>>> responses;

  @override
  State<_MultiPageProbeWidget> createState() => _MultiPageProbeWidgetState();
}

class _MultiPageProbeWidgetState
    extends MultiPageLoadingState<_MultiPageProbeWidget, int> {
  List<int>? lastRendered;

  @override
  Future<Res<List<int>>> loadData(int page) async => widget.responses[page]!;

  @override
  Widget buildContent(BuildContext context, List<int> data) {
    lastRendered = data;
    return ListView(children: data.map((e) => Text('$e')).toList());
  }
}

class _ErrorProbeWidget extends StatefulWidget {
  const _ErrorProbeWidget({
    required this.stepSignals,
    required this.steps,
    required this.stateKey,
  }) : super(key: stateKey);

  final List<Completer<void>> stepSignals;
  final List<Res<String>> steps;
  final GlobalKey<_ErrorProbeWidgetState> stateKey;

  @override
  State<_ErrorProbeWidget> createState() => _ErrorProbeWidgetState();
}

class _ErrorProbeWidgetState extends LoadingState<_ErrorProbeWidget, String> {
  int _index = 0;

  @override
  Future<Res<String>> loadData() async {
    final i = _index++;
    await widget.stepSignals[i].future;
    return widget.steps[i];
  }

  @override
  Widget buildContent(BuildContext context, String data) => Text(data);

  @override
  Widget buildError() => const Material(child: Text('error'));
}

void main() {
  setUp(() {
    app_diag.AppDiagnostics.configureSinksForTesting(const []);
  });

  tearDown(() {
    app_diag.AppDiagnostics.resetForTesting();
  });

  testWidgets('LoadingState ignores stale load result after retry', (
    tester,
  ) async {
    final stateKey = GlobalKey<_SequencedLoadWidgetState>();
    final first = Completer<void>();
    final second = Completer<void>();

    await tester.pumpWidget(
      MaterialApp(
        home: _SequencedLoadWidget(
          stateKey: stateKey,
          stepSignals: [first, second],
          steps: const [Res('old'), Res('new')],
        ),
      ),
    );
    await tester.pump();

    stateKey.currentState!.retry();
    await tester.pump();

    second.complete();
    await tester.pump();
    await tester.pump();

    first.complete();
    await tester.pump();
    await tester.pump();

    expect(find.text('new'), findsOneWidget);
    expect(find.text('old'), findsNothing);
  });

  testWidgets('LoadingState stale error does not overwrite newer success', (
    tester,
  ) async {
    final stateKey = GlobalKey<_SequencedLoadWidgetState>();
    final first = Completer<void>();
    final second = Completer<void>();
    final third = Completer<void>()..complete();
    final fourth = Completer<void>()..complete();
    final fifth = Completer<void>()..complete();

    await tester.pumpWidget(
      MaterialApp(
        home: _SequencedLoadWidget(
          stateKey: stateKey,
          stepSignals: [first, second, third, fourth, fifth],
          steps: const [
            Res.error('token=abc'),
            Res('fresh'),
            Res.error('token=abc'),
            Res.error('token=abc'),
            Res.error('token=abc'),
          ],
        ),
      ),
    );
    await tester.pump();

    stateKey.currentState!.retry();
    await tester.pump();

    second.complete();
    await tester.pump();
    await tester.pump();

    first.complete();
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('fresh'), findsOneWidget);
    expect(find.text('Network Error'), findsNothing);
  });

  testWidgets('MultiPageLoadingState appends using a new list instance', (
    tester,
  ) async {
    final stateKey = GlobalKey<_MultiPageProbeWidgetState>();
    final initial = [1, 2];
    await tester.pumpWidget(
      MaterialApp(
        home: _MultiPageProbeWidget(
          stateKey: stateKey,
          responses: {
            1: Res(initial, subData: 2),
            2: const Res([3, 4], subData: 2),
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    final firstInstance = stateKey.currentState!.data;
    await stateKey.currentState!.nextPage();
    await tester.pump();

    final secondInstance = stateKey.currentState!.data;
    expect(identical(firstInstance, secondInstance), isFalse);
    expect(secondInstance, equals([1, 2, 3, 4]));
  });

  test('redact logs removes bearer token api key and set-cookie values', () {
    const raw = '''
Authorization: Bearer abc.def.ghi
api_key=secret123
x-api-key: top-secret
set-cookie: session=abc123; Path=/
https://user:pass@example.com/path
''';

    final redacted = redactLoadingDiagnosticsForExport(raw);
    expect(redacted.toLowerCase(), contains('authorization=[redacted]'));
    expect(redacted.toLowerCase(), contains('api_key=[redacted]'));
    expect(redacted.toLowerCase(), contains('x-api-key=[redacted]'));
    expect(redacted.toLowerCase(), contains('set-cookie=[redacted]'));
    expect(
      redacted,
      contains('https://[redacted]:[redacted]@example.com/path'),
    );
    expect(redacted, isNot(contains('secret123')));
    expect(redacted, isNot(contains('top-secret')));
    expect(redacted, isNot(contains('session=abc123')));
    expect(redacted.toLowerCase(), isNot(contains('bearer abc.def.ghi')));
  });

  testWidgets(
    'LoadingState emits ui.error.visible when visible error renders',
    (tester) async {
      final stateKey = GlobalKey<_ErrorProbeWidgetState>();
      final first = Completer<void>()..complete();
      final second = Completer<void>()..complete();
      final third = Completer<void>()..complete();
      final fourth = Completer<void>()..complete();

      await tester.pumpWidget(
        MaterialApp(
          home: _ErrorProbeWidget(
            stateKey: stateKey,
            stepSignals: [first, second, third, fourth],
            steps: const [
              Res.error('token=abc'),
              Res.error('token=abc'),
              Res.error('token=abc'),
              Res.error('token=abc'),
            ],
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      final events = app_diag.AppDiagnostics.recent(channel: 'ui.error');
      expect(
        events.any(
          (e) =>
              e.message == 'ui.error.visible' &&
              e.level == app_diag.DiagnosticLevel.error,
        ),
        isTrue,
      );
      final event = events.last;
      expect(event.data['pageOwner'], contains('_ErrorProbeWidget'));
      expect(
        event.data['sanitizedMessage'].toString().contains('token=abc'),
        isFalse,
      );
    },
  );

  testWidgets(
    'LoadingState suppresses ui.error.visible for LOCAL_COMIC_MISSING',
    (tester) async {
      final stateKey = GlobalKey<_ErrorProbeWidgetState>();
      final first = Completer<void>()..complete();
      final second = Completer<void>()..complete();
      final third = Completer<void>()..complete();
      final fourth = Completer<void>()..complete();

      await tester.pumpWidget(
        MaterialApp(
          home: _ErrorProbeWidget(
            stateKey: stateKey,
            stepSignals: [first, second, third, fourth],
            steps: const [
              Res.error('LOCAL_COMIC_MISSING'),
              Res.error('LOCAL_COMIC_MISSING'),
              Res.error('LOCAL_COMIC_MISSING'),
              Res.error('LOCAL_COMIC_MISSING'),
            ],
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      final events = app_diag.AppDiagnostics.recent(channel: 'ui.error');
      expect(events.any((e) => e.message == 'ui.error.visible'), isFalse);
      expect(find.text('error'), findsOneWidget);
    },
  );
}
