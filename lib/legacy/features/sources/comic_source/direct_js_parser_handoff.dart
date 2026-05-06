import 'dart:io';

import 'package:venera/features/sources/comic_source/comic_source.dart';
import 'package:venera/features/sources/comic_source/direct_js_source_validator.dart';

const sourceInstallBlockedCode = 'SOURCE_INSTALL_BLOCKED';
const sourceKeyMismatchCode = 'SOURCE_KEY_MISMATCH';

typedef DirectJsCreateAndParse =
    Future<ComicSource> Function(String sourceJs, String fileName);
typedef DirectJsRegisterSource = void Function(ComicSource source);

class DirectJsParserHandoff {
  DirectJsParserHandoff({
    required DirectJsCreateAndParse createAndParse,
    required DirectJsRegisterSource registerSource,
  }) : _createAndParse = createAndParse,
       _registerSource = registerSource;

  final DirectJsCreateAndParse _createAndParse;
  final DirectJsRegisterSource _registerSource;

  Future<SourceCommandResult> handoff({
    required File committedFile,
    required String sourceScript,
    required String fileName,
    required String validatedSourceKey,
  }) async {
    try {
      final parsed = await _createAndParse(sourceScript, fileName);
      if (parsed.key.trim() != validatedSourceKey.trim()) {
        await _safeRollback(committedFile);
        return const SourceCommandFailed(
          code: sourceKeyMismatchCode,
          message: 'Parsed source key mismatches validated source key',
        );
      }
      _registerSource(parsed);
      return SourceCommandSuccess(
        metadata: DirectJsValidationMetadata(
          sourceKey: parsed.key,
          name: parsed.name,
          version: parsed.version,
        ),
      );
    } catch (_) {
      await _safeRollback(committedFile);
      return const SourceCommandFailed(
        code: sourceInstallBlockedCode,
        message: 'Parser handoff failed and committed file was rolled back',
      );
    }
  }

  Future<void> _safeRollback(File file) async {
    if (await file.exists()) {
      await file.delete();
    }
  }
}
