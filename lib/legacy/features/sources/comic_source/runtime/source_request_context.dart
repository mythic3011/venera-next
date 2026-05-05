class SourceRequestContext {
  final String sourceKey;
  final String requestId;
  final String? accountProfileId;
  final int? accountRevision;
  final String? headerProfile;
  final DateTime createdAt;

  const SourceRequestContext({
    required this.sourceKey,
    required this.requestId,
    required this.createdAt,
    this.accountProfileId,
    this.accountRevision,
    this.headerProfile,
  });
}
