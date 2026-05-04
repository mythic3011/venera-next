import 'package:flutter_test/flutter_test.dart';
import 'package:venera/features/sources/comic_source/runtime.dart';

void main() {
  test('existing runtime codes map to target SOURCE meanings', () {
    expect(
      SourceRuntimeCodes.toSourceMeaning(SourceRuntimeCodes.legacyUnknown),
      SourceRuntimeCodes.sourceRuntimeException,
    );
    expect(
      SourceRuntimeCodes.toSourceMeaning(
        SourceRuntimeCodes.legacyNetworkFailure,
      ),
      SourceRuntimeCodes.sourceUnavailable,
    );
    expect(
      SourceRuntimeCodes.toSourceMeaning(SourceRuntimeCodes.requestTimeout),
      SourceRuntimeCodes.sourceUnavailable,
    );
    expect(
      SourceRuntimeCodes.toSourceMeaning(
        SourceRuntimeCodes.httpUnexpectedStatus,
      ),
      SourceRuntimeCodes.sourceUnavailable,
    );
    expect(
      SourceRuntimeCodes.toSourceMeaning(
        SourceRuntimeCodes.parserInvalidContent,
      ),
      SourceRuntimeCodes.sourceSchemaInvalid,
    );
  });

  test('runtime error exposes mapped source meaning', () {
    final error = SourceRuntimeError(
      code: SourceRuntimeCodes.legacyUnknown,
      message: 'Legacy source runtime failure.',
      sourceKey: 'copymanga',
      stage: SourceRuntimeStage.legacy,
    );

    expect(error.sourceMeaningCode, SourceRuntimeCodes.sourceRuntimeException);
    expect(
      error.toUiMessage(),
      '${SourceRuntimeCodes.sourceRuntimeException}:Legacy source runtime failure.',
    );
  });

  test('typed runtime result envelope supports success and failure', () {
    final success = SourceRuntimeSuccess<int>(1);
    final failure = SourceRuntimeFailure<int>(
      SourceRuntimeError(
        code: SourceRuntimeCodes.legacyUnknown,
        message: 'boom',
        sourceKey: 'copymanga',
        stage: SourceRuntimeStage.legacy,
      ),
    );

    expect(success.value, 1);
    expect(failure.error.code, SourceRuntimeCodes.legacyUnknown);
  });
}
