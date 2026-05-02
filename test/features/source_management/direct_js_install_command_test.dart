import 'package:flutter_test/flutter_test.dart';
import 'package:venera/features/sources/comic_source/direct_js_install_command.dart';
import 'package:venera/features/sources/comic_source/direct_js_source_validator.dart';

void main() {
  group('Direct JS install command guards (D3c2)', () {
    late _FakeDirectJsSourceWriteAdapter adapter;
    late DirectJsInstallCommand command;

    setUp(() {
      adapter = _FakeDirectJsSourceWriteAdapter();
      command = DirectJsInstallCommand(adapter: adapter);
    });

    DirectJsInstallRequest buildRequest({
      bool confirmInstall = true,
      bool allowOverwrite = false,
      String validatedKey = 'demo_source',
      String parsedKey = 'demo_source',
    }) {
      return DirectJsInstallRequest(
        sourceUrl: 'https://example.com/demo_source.js',
        sourceScript: 'class Demo extends ComicSource {}',
        validatedMetadata: DirectJsValidationMetadata(sourceKey: validatedKey),
        parsedSourceKey: parsedKey,
        confirmInstall: confirmInstall,
        allowOverwrite: allowOverwrite,
      );
    }

    test(
      'direct js install command blocks when confirmInstall is false',
      () async {
        final result = await command.execute(buildRequest(confirmInstall: false));
        expect(result, isA<SourceCommandFailed>());
        expect(
          (result as SourceCommandFailed).code,
          sourceInstallBlockedCode,
        );
        expect(adapter.writeCalls, 0);
      },
    );

    test(
      'direct js install command blocks source key collision without overwrite confirmation',
      () async {
        adapter.existingKeys.add('demo_source');
        final result = await command.execute(
          buildRequest(confirmInstall: true, allowOverwrite: false),
        );
        expect(result, isA<SourceCommandFailed>());
        expect((result as SourceCommandFailed).code, sourceInstallKeyCollisionCode);
        expect(adapter.writeCalls, 0);
      },
    );

    test(
      'direct js install command keeps collision blocked even with overwrite until write adapter exists',
      () async {
        adapter.existingKeys.add('demo_source');
        final result = await command.execute(
          buildRequest(confirmInstall: true, allowOverwrite: true),
        );
        expect(result, isA<SourceCommandFailed>());
        expect((result as SourceCommandFailed).code, sourceInstallBlockedCode);
        expect(adapter.writeCalls, 0);
      },
    );

    test(
      'direct js install command blocks source key mismatch between validation and parsed payload',
      () async {
        final result = await command.execute(
          buildRequest(validatedKey: 'source_a', parsedKey: 'source_b'),
        );
        expect(result, isA<SourceCommandFailed>());
        expect((result as SourceCommandFailed).code, sourceKeyMismatchCode);
        expect(adapter.writeCalls, 0);
      },
    );

    test(
      'direct js install command dry run does not write installed source files',
      () async {
        final result = await command.execute(buildRequest());
        expect(result, isA<SourceCommandFailed>());
        expect((result as SourceCommandFailed).code, sourceInstallBlockedCode);
        expect(adapter.writeCalls, 0);
      },
    );

    test(
      'direct js install command dry run does not mutate ComicSourceManager state',
      () async {
        final beforeKeys = Set<String>.from(adapter.existingKeys);
        final result = await command.execute(buildRequest());
        expect(result, isA<SourceCommandFailed>());
        expect(adapter.existingKeys, beforeKeys);
        expect(adapter.writeCalls, 0);
      },
    );
  });
}

class _FakeDirectJsSourceWriteAdapter implements DirectJsSourceWriteAdapter {
  final Set<String> existingKeys = <String>{};
  int writeCalls = 0;

  @override
  Future<bool> hasInstalledSourceKey(String sourceKey) async {
    return existingKeys.contains(sourceKey);
  }

  @override
  Future<void> writeInstalledSource(DirectJsInstallRequest request) async {
    writeCalls++;
    existingKeys.add(request.parsedSourceKey);
  }
}
