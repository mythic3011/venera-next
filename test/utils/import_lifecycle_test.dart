import 'package:flutter_test/flutter_test.dart';
import 'package:venera/foundation/diagnostics/diagnostics.dart';
import 'package:venera/utils/import_lifecycle.dart';

void main() {
  setUp(() {
    AppDiagnostics.configureSinksForTesting(const []);
  });

  tearDown(() {
    AppDiagnostics.resetForTesting();
  });

  test('import lifecycle start emits sanitized started event', () {
    final trace = ImportLifecycleTrace.start(
      operation: 'import.cbz.file',
      sourceName: 'comic.cbz',
      sourceType: 'cbz',
      data: const {'cachePath': '/tmp/venera/cache/a'},
    );

    final started = DevDiagnosticsApi.recent(
      channel: 'import.lifecycle',
    ).firstWhere((event) => event.message == 'import.lifecycle.started');

    expect(started.data['importId'], trace.id);
    expect(started.data['operation'], 'import.cbz.file');
    expect(started.data['sourceName'], 'comic.cbz');
    expect(started.data['sourceType'], 'cbz');
    expect(started.data.containsKey('cachePath'), isFalse);
    expect(started.data['cachePathHash']?.toString().isNotEmpty, isTrue);
    expect(started.data['cachePathName'], 'a');
    expect(started.data['cachePathRootAlias'], '<CACHE>');
  });

  test(
    'import lifecycle phase/failed/completed keep importId and redact paths',
    () {
      final trace = ImportLifecycleTrace.start(
        operation: 'import.local_downloads',
      );

      trace.phase(
        'scan',
        data: const {'rootPath': '/Users/test/app/data/local'},
      );
      trace.failed(
        StateError('failed'),
        phase: 'scan',
        data: const {'targetDirectory': '/Users/test/app/data/local/comic-a'},
      );
      trace.completed(
        data: const {'destinationRoot': '/Users/test/app/data/local'},
      );

      final events = DevDiagnosticsApi.recent(channel: 'import.lifecycle');
      final started = events.firstWhere(
        (event) => event.message == 'import.lifecycle.started',
      );
      final phase = events.firstWhere(
        (event) =>
            event.message == 'import.lifecycle.phase' &&
            event.data['phase'] == 'scan',
      );
      final failed = events.firstWhere(
        (event) => event.message == 'import.lifecycle.failed',
      );
      final completed = events.firstWhere(
        (event) => event.message == 'import.lifecycle.completed',
      );

      expect(phase.data['importId'], started.data['importId']);
      expect(failed.data['importId'], started.data['importId']);
      expect(completed.data['importId'], started.data['importId']);

      expect(phase.data.containsKey('rootPath'), isFalse);
      expect(failed.data.containsKey('targetDirectory'), isFalse);
      expect(completed.data.containsKey('destinationRoot'), isFalse);
      expect(phase.data['rootPathHash']?.toString().isNotEmpty, isTrue);
      expect(failed.data['targetDirectoryHash']?.toString().isNotEmpty, isTrue);
      expect(
        completed.data['destinationRootHash']?.toString().isNotEmpty,
        isTrue,
      );
    },
  );
}
