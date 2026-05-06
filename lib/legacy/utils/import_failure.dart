import 'package:venera/utils/translations.dart';

class ImportFailure implements Exception {
  ImportFailure._({
    required this.code,
    required this.message,
    this.data = const {},
    required this.uiMessage,
  });

  final String code;
  final String message;
  final Map<String, Object?> data;
  final String uiMessage;

  ImportFailure.copyFailed(
    String message, {
    Map<String, Object?> data = const {},
    String? uiMessage,
  })
    : this._(
        code: 'IMPORT_COPY_FAILED',
        message: message,
        data: data,
        uiMessage: uiMessage ?? "Failed to copy comics".tl,
      );

  ImportFailure.destinationExists({
    required String comicTitle,
    required String targetDirectory,
  }) : this._(
         code: 'IMPORT_DESTINATION_EXISTS',
         message: 'Destination already exists for "$comicTitle"',
         data: <String, Object?>{
           'comicTitle': comicTitle,
           'targetDirectory': targetDirectory,
           'reason': 'destination_exists',
           'action': 'blocked',
         },
         uiMessage: "Comic already exists".tl,
       );

  ImportFailure.duplicateDetected({
    required String comicTitle,
    required String targetDirectory,
    String? existingComicId,
  }) : this._(
         code: 'IMPORT_DUPLICATE_DETECTED',
         message: 'Comic "$comicTitle" already exists',
         data: <String, Object?>{
           'comicTitle': comicTitle,
           'targetDirectory': targetDirectory,
           if (existingComicId != null) 'existingComicId': existingComicId,
           'action': 'blocked',
         },
         uiMessage: "Comic already exists".tl,
       );

  ImportFailure.missingFiles({
    required String comicTitle,
    required String targetDirectory,
  }) : this._(
         code: 'IMPORT_MISSING_FILES',
         message: 'Import path is missing or invalid',
         data: <String, Object?>{
           'comicTitle': comicTitle,
           'targetDirectory': targetDirectory,
           'action': 'blocked',
         },
         uiMessage: "Local path not found".tl,
       );

  @override
  String toString() => '$code: $message';
}
