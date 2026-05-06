import 'dart:convert';
import 'dart:io';

import 'package:venera/features/sources/comic_source/comic_source.dart';
import 'package:venera/features/sources/comic_source/direct_js_parser_handoff.dart';
import 'package:venera/features/sources/comic_source/direct_js_staged_source_writer.dart';
import 'package:venera/features/sources/comic_source/direct_js_source_validator.dart';
import 'package:venera/foundation/app/app.dart';

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

  Future<SourceCommandResult> writeInstalledSource(DirectJsInstallRequest request);
}

class ProductionDirectJsSourceWriteAdapter implements DirectJsSourceWriteAdapter {
  ProductionDirectJsSourceWriteAdapter({
    Directory? activeDir,
    Directory? stagedDir,
    DirectJsStagedSourceWriter? stagedWriter,
    DirectJsParserHandoff? parserHandoff,
    Future<bool> Function(String sourceKey)? installedKeyLookup,
  }) : _activeDir =
           activeDir ?? Directory('${App.dataPath}/comic_source'),
       _stagedDir =
           stagedDir ?? Directory('${App.dataPath}/comic_source_staging'),
       _stagedWriter =
           stagedWriter ??
           DirectJsStagedSourceWriter(
             activeDir: activeDir ?? Directory('${App.dataPath}/comic_source'),
             stagedDir:
                 stagedDir ??
                 Directory('${App.dataPath}/comic_source_staging'),
           ),
       _parserHandoff =
           parserHandoff ??
           DirectJsParserHandoff(
             createAndParse: (sourceJs, committedFilePath) {
               return ComicSourceParser().parse(sourceJs, committedFilePath);
             },
             registerSource: (source) {
               ComicSourceManager().add(source);
             },
           ),
       _installedKeyLookup =
           installedKeyLookup ??
           ((sourceKey) async {
             final existingFile = File(
               '${(activeDir ?? Directory('${App.dataPath}/comic_source')).path}/$sourceKey.js',
             );
             return ComicSource.find(sourceKey) != null ||
                 await existingFile.exists();
           });

  final Directory _activeDir;
  final Directory _stagedDir;
  final DirectJsStagedSourceWriter _stagedWriter;
  final DirectJsParserHandoff _parserHandoff;
  final Future<bool> Function(String sourceKey) _installedKeyLookup;

  @override
  Future<bool> hasInstalledSourceKey(String sourceKey) {
    return _installedKeyLookup(sourceKey.trim());
  }

  @override
  Future<SourceCommandResult> writeInstalledSource(
    DirectJsInstallRequest request,
  ) async {
    final validatedKey = request.validatedMetadata.sourceKey.trim();
    final activeFileName = '$validatedKey.js';
    try {
      await _activeDir.create(recursive: true);
      await _stagedDir.create(recursive: true);
      final stagedFile = await _stagedWriter.createStagedFile(
        fileName: activeFileName,
        bytes: utf8.encode(request.sourceScript),
      );
      final committedFile = await _stagedWriter.commitStagedFile(
        stagedFile,
        activeFileName: activeFileName,
      );
      return _parserHandoff.handoff(
        committedFile: committedFile,
        sourceScript: request.sourceScript,
        fileName: activeFileName,
        validatedSourceKey: validatedKey,
      );
    } on DirectJsStagedSourceWriterException catch (error) {
      final isCollision = error.message.contains('already exists');
      return SourceCommandFailed(
        code: isCollision
            ? sourceInstallKeyCollisionCode
            : sourceInstallBlockedCode,
        message: error.message,
      );
    }
  }
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
    return _adapter.writeInstalledSource(request);
  }
}
