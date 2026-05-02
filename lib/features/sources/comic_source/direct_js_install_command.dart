import 'package:venera/features/sources/comic_source/direct_js_source_validator.dart';

const sourceInstallBlockedCode = 'SOURCE_INSTALL_BLOCKED';
const sourceInstallKeyCollisionCode = 'SOURCE_KEY_COLLISION';
const sourceKeyMismatchCode = 'SOURCE_KEY_MISMATCH';

class DirectJsInstallRequest {
  const DirectJsInstallRequest({
    required this.sourceUrl,
    required this.sourceScript,
    required this.validatedMetadata,
    required this.parsedSourceKey,
    required this.confirmInstall,
    this.allowOverwrite = false,
  });

  final String sourceUrl;
  final String sourceScript;
  final DirectJsValidationMetadata validatedMetadata;
  final String parsedSourceKey;
  final bool confirmInstall;
  final bool allowOverwrite;
}

abstract class DirectJsSourceWriteAdapter {
  Future<bool> hasInstalledSourceKey(String sourceKey);

  Future<void> writeInstalledSource(DirectJsInstallRequest request);
}

class DirectJsInstallCommand {
  const DirectJsInstallCommand({required DirectJsSourceWriteAdapter adapter})
    : _adapter = adapter;

  final DirectJsSourceWriteAdapter _adapter;

  Future<SourceCommandResult> execute(DirectJsInstallRequest request) async {
    if (!request.confirmInstall) {
      return const SourceCommandFailed(
        code: sourceInstallBlockedCode,
        message: 'Direct JS install requires explicit confirmation',
      );
    }

    final validated = request.validatedMetadata.sourceKey.trim();
    final parsed = request.parsedSourceKey.trim();
    if (validated != parsed) {
      return SourceCommandFailed(
        code: sourceKeyMismatchCode,
        message:
            'Validated source key "$validated" does not match parsed key "$parsed"',
      );
    }

    final exists = await _adapter.hasInstalledSourceKey(parsed);
    if (exists && !request.allowOverwrite) {
      return SourceCommandFailed(
        code: sourceInstallKeyCollisionCode,
        message: 'Source key collision: $parsed',
      );
    }

    return const SourceCommandFailed(
      code: sourceInstallBlockedCode,
      message: 'Direct JS install write path is disabled in D3c2',
    );
  }
}
