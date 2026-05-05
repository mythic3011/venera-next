abstract final class SourceRuntimeCodes {
  static const legacyUnknown = 'LEGACY_UNKNOWN';
  static const legacyNetworkFailure = 'LEGACY_NETWORK_FAILURE';
  static const requestTimeout = 'REQUEST_TIMEOUT';
  static const httpUnexpectedStatus = 'HTTP_UNEXPECTED_STATUS';
  static const parserInvalidContent = 'PARSER_INVALID_CONTENT';
  static const settingsInvalid = 'SETTINGS_INVALID';

  static const sourceBlocked = 'SOURCE_BLOCKED';
  static const sourceRequiresOfficialApp = 'SOURCE_REQUIRES_OFFICIAL_APP';
  static const sourceAuthRequired = 'SOURCE_AUTH_REQUIRED';
  static const sourceForbidden = 'SOURCE_FORBIDDEN';
  static const sourceNotFound = 'SOURCE_NOT_FOUND';
  static const sourceUnavailable = 'SOURCE_UNAVAILABLE';
  static const sourceSchemaInvalid = 'SOURCE_SCHEMA_INVALID';
  static const sourceRateLimited = 'SOURCE_RATE_LIMITED';
  static const sourceSettingsInvalid = 'SOURCE_SETTINGS_INVALID';
  static const sourceCapabilityUnsupported = 'SOURCE_CAPABILITY_UNSUPPORTED';
  static const sourceRuntimeException = 'SOURCE_RUNTIME_EXCEPTION';

  static String toSourceMeaning(String code) {
    if (code.startsWith('SOURCE_')) {
      return code;
    }
    switch (code) {
      case requestTimeout:
      case legacyNetworkFailure:
      case httpUnexpectedStatus:
        return sourceUnavailable;
      case parserInvalidContent:
        return sourceSchemaInvalid;
      case settingsInvalid:
        return sourceSettingsInvalid;
      case legacyUnknown:
      default:
        return sourceRuntimeException;
    }
  }
}
