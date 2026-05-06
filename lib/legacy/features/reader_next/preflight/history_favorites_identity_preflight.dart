import 'dart:convert';

import 'package:crypto/crypto.dart';

enum IdentityRecordKind { history, favorite }

enum SourceRefValidationCode {
  valid,
  missing,
  malformed,
  canonicalLeakAsUpstream,
}

enum RemediationAction {
  none,
  eligibleForFutureExplicitBackfill,
  requiresUserReopenFromDetail,
  requiresLegacyImporterData,
  blockedMalformedIdentity,
}

extension on IdentityRecordKind {
  String get wireValue => switch (this) {
    IdentityRecordKind.history => 'history',
    IdentityRecordKind.favorite => 'favorite',
  };
}

extension on SourceRefValidationCode {
  String get wireValue => switch (this) {
    SourceRefValidationCode.valid => 'valid',
    SourceRefValidationCode.missing => 'missing',
    SourceRefValidationCode.malformed => 'malformed',
    SourceRefValidationCode.canonicalLeakAsUpstream =>
      'canonicalLeakAsUpstream',
  };
}

extension on RemediationAction {
  String get wireValue => switch (this) {
    RemediationAction.none => 'none',
    RemediationAction.eligibleForFutureExplicitBackfill =>
      'eligibleForFutureExplicitBackfill',
    RemediationAction.requiresUserReopenFromDetail =>
      'requiresUserReopenFromDetail',
    RemediationAction.requiresLegacyImporterData =>
      'requiresLegacyImporterData',
    RemediationAction.blockedMalformedIdentity => 'blockedMalformedIdentity',
  };
}

class ExplicitSourceRefSnapshot {
  const ExplicitSourceRefSnapshot({
    required this.sourceKey,
    required this.upstreamComicRefId,
    this.chapterRefId,
  });

  final String sourceKey;
  final String upstreamComicRefId;
  final String? chapterRefId;
}

class IdentityCoverageInput {
  const IdentityCoverageInput._({
    required this.kind,
    required this.recordId,
    required this.sourceKey,
    this.folderName,
    this.canonicalComicId,
    this.sourceRef,
    this.hasImporterOwnedExplicitSnapshot = false,
    this.explicitSnapshotAlreadyPersisted = false,
  });

  factory IdentityCoverageInput.history({
    required String recordId,
    required String sourceKey,
    String? folderName,
    String? canonicalComicId,
    ExplicitSourceRefSnapshot? sourceRef,
    bool hasImporterOwnedExplicitSnapshot = false,
    bool explicitSnapshotAlreadyPersisted = false,
  }) {
    return IdentityCoverageInput._(
      kind: IdentityRecordKind.history,
      recordId: recordId,
      sourceKey: sourceKey,
      folderName: folderName,
      canonicalComicId: canonicalComicId,
      sourceRef: sourceRef,
      hasImporterOwnedExplicitSnapshot: hasImporterOwnedExplicitSnapshot,
      explicitSnapshotAlreadyPersisted: explicitSnapshotAlreadyPersisted,
    );
  }

  factory IdentityCoverageInput.favorite({
    required String recordId,
    required String sourceKey,
    String? folderName,
    String? canonicalComicId,
    ExplicitSourceRefSnapshot? sourceRef,
    bool hasImporterOwnedExplicitSnapshot = false,
    bool explicitSnapshotAlreadyPersisted = false,
  }) {
    return IdentityCoverageInput._(
      kind: IdentityRecordKind.favorite,
      recordId: recordId,
      sourceKey: sourceKey,
      folderName: folderName,
      canonicalComicId: canonicalComicId,
      sourceRef: sourceRef,
      hasImporterOwnedExplicitSnapshot: hasImporterOwnedExplicitSnapshot,
      explicitSnapshotAlreadyPersisted: explicitSnapshotAlreadyPersisted,
    );
  }

  final IdentityRecordKind kind;
  final String recordId;
  final String sourceKey;
  final String? folderName;
  final String? canonicalComicId;
  final ExplicitSourceRefSnapshot? sourceRef;
  final bool hasImporterOwnedExplicitSnapshot;
  final bool explicitSnapshotAlreadyPersisted;
}

class IdentityCoverageResult {
  const IdentityCoverageResult({
    required this.kind,
    required this.recordId,
    required this.sourceRefValidationCode,
    required this.remediationAction,
    required this.sourceKey,
    required this.hasSourceRef,
    this.folderName,
    this.explicitCanonicalComicId,
    this.explicitUpstreamComicRefId,
    this.explicitChapterRefId,
    this.observedIdentityFingerprint,
    required this.canonicalComicIdRedacted,
    required this.upstreamComicRefIdRedacted,
    required this.chapterRefIdRedacted,
  });

  final IdentityRecordKind kind;
  final String recordId;
  final SourceRefValidationCode sourceRefValidationCode;
  final RemediationAction remediationAction;
  final String sourceKey;
  final bool hasSourceRef;
  final String? folderName;
  final String? explicitCanonicalComicId;
  final String? explicitUpstreamComicRefId;
  final String? explicitChapterRefId;
  final String? observedIdentityFingerprint;
  final String canonicalComicIdRedacted;
  final String upstreamComicRefIdRedacted;
  final String chapterRefIdRedacted;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'recordKind': kind.wireValue,
      'recordId': recordId,
      'sourceKey': sourceKey,
      'hasSourceRef': hasSourceRef,
      if (folderName != null) 'folderName': folderName,
      'sourceRefValidationCode': sourceRefValidationCode.wireValue,
      if (explicitCanonicalComicId != null)
        'explicitCanonicalComicId': explicitCanonicalComicId,
      if (explicitUpstreamComicRefId != null)
        'explicitUpstreamComicRefId': explicitUpstreamComicRefId,
      if (explicitChapterRefId != null)
        'explicitChapterRefId': explicitChapterRefId,
      if (observedIdentityFingerprint != null)
        'observedIdentityFingerprint': observedIdentityFingerprint,
      'canonicalComicIdRedacted': canonicalComicIdRedacted,
      'upstreamComicRefIdRedacted': upstreamComicRefIdRedacted,
      'chapterRefIdRedacted': chapterRefIdRedacted,
      'proposalAction': remediationAction.wireValue,
    };
  }
}

class IdentityCoverageAggregate {
  const IdentityCoverageAggregate({
    required this.total,
    required this.valid,
    required this.missing,
    required this.malformed,
    required this.canonicalLeakAsUpstream,
  });

  final int total;
  final int valid;
  final int missing;
  final int malformed;
  final int canonicalLeakAsUpstream;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'valid': valid,
      'missing': missing,
      'malformed': malformed,
      'canonicalLeakAsUpstream': canonicalLeakAsUpstream,
    };
  }
}

class IdentityCoverageReport {
  const IdentityCoverageReport({
    required this.schemaVersion,
    required this.dryRun,
    required this.aggregate,
    required this.results,
  });

  final int schemaVersion;
  final bool dryRun;
  final IdentityCoverageAggregate aggregate;
  final List<IdentityCoverageResult> results;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'schemaVersion': schemaVersion,
      'dryRun': dryRun,
      'aggregate': aggregate.toJson(),
      'results': results.map((entry) => entry.toJson()).toList(growable: false),
    };
  }
}

class HistoryFavoritesIdentityCoverageScanner {
  const HistoryFavoritesIdentityCoverageScanner();

  IdentityCoverageResult scan(IdentityCoverageInput input) {
    final sourceRef = input.sourceRef;
    if (sourceRef == null) {
      return IdentityCoverageResult(
        kind: input.kind,
        recordId: input.recordId,
        sourceRefValidationCode: SourceRefValidationCode.missing,
        remediationAction: input.hasImporterOwnedExplicitSnapshot
            ? RemediationAction.requiresLegacyImporterData
            : RemediationAction.requiresUserReopenFromDetail,
        sourceKey: input.sourceKey,
        hasSourceRef: false,
        folderName: input.folderName,
        explicitCanonicalComicId: null,
        explicitUpstreamComicRefId: null,
        explicitChapterRefId: null,
        observedIdentityFingerprint: null,
        canonicalComicIdRedacted: _redact(input.canonicalComicId ?? ''),
        upstreamComicRefIdRedacted: '<missing>',
        chapterRefIdRedacted: '<missing>',
      );
    }

    if (sourceRef.sourceKey.trim().isEmpty ||
        sourceRef.upstreamComicRefId.trim().isEmpty) {
      return IdentityCoverageResult(
        kind: input.kind,
        recordId: input.recordId,
        sourceRefValidationCode: SourceRefValidationCode.malformed,
        remediationAction: RemediationAction.blockedMalformedIdentity,
        sourceKey: input.sourceKey,
        hasSourceRef: true,
        folderName: input.folderName,
        explicitCanonicalComicId: null,
        explicitUpstreamComicRefId: null,
        explicitChapterRefId: null,
        observedIdentityFingerprint: null,
        canonicalComicIdRedacted: _redact(input.canonicalComicId ?? ''),
        upstreamComicRefIdRedacted: _redact(sourceRef.upstreamComicRefId),
        chapterRefIdRedacted: _redact(sourceRef.chapterRefId ?? ''),
      );
    }

    if (sourceRef.upstreamComicRefId.startsWith('remote:')) {
      return IdentityCoverageResult(
        kind: input.kind,
        recordId: input.recordId,
        sourceRefValidationCode:
            SourceRefValidationCode.canonicalLeakAsUpstream,
        remediationAction: RemediationAction.blockedMalformedIdentity,
        sourceKey: input.sourceKey,
        hasSourceRef: true,
        folderName: input.folderName,
        explicitCanonicalComicId: null,
        explicitUpstreamComicRefId: null,
        explicitChapterRefId: null,
        observedIdentityFingerprint: null,
        canonicalComicIdRedacted: _redact(input.canonicalComicId ?? ''),
        upstreamComicRefIdRedacted: _redact(sourceRef.upstreamComicRefId),
        chapterRefIdRedacted: _redact(sourceRef.chapterRefId ?? ''),
      );
    }

    final explicitCanonicalComicId =
        'remote:${sourceRef.sourceKey}:${sourceRef.upstreamComicRefId}';
    final explicitChapterRefId = sourceRef.chapterRefId ?? '';
    final observedIdentityFingerprint = _fingerprint(<String>[
      input.kind.wireValue,
      input.folderName ?? '',
      input.recordId,
      input.sourceKey,
      explicitCanonicalComicId,
      sourceRef.upstreamComicRefId,
      explicitChapterRefId,
    ]);
    final remediationAction = input.explicitSnapshotAlreadyPersisted
        ? RemediationAction.none
        : RemediationAction.eligibleForFutureExplicitBackfill;
    return IdentityCoverageResult(
      kind: input.kind,
      recordId: input.recordId,
      sourceRefValidationCode: SourceRefValidationCode.valid,
      remediationAction: remediationAction,
      sourceKey: input.sourceKey,
      hasSourceRef: true,
      folderName: input.folderName,
      explicitCanonicalComicId: explicitCanonicalComicId,
      explicitUpstreamComicRefId: sourceRef.upstreamComicRefId,
      explicitChapterRefId: sourceRef.chapterRefId ?? '',
      observedIdentityFingerprint: observedIdentityFingerprint,
      canonicalComicIdRedacted: _redact(input.canonicalComicId ?? ''),
      upstreamComicRefIdRedacted: _redact(sourceRef.upstreamComicRefId),
      chapterRefIdRedacted: _redact(sourceRef.chapterRefId ?? ''),
    );
  }

  IdentityCoverageReport buildReport(Iterable<IdentityCoverageInput> inputs) {
    final results = inputs.map(scan).toList(growable: false);
    var valid = 0;
    var missing = 0;
    var malformed = 0;
    var canonicalLeakAsUpstream = 0;
    for (final result in results) {
      switch (result.sourceRefValidationCode) {
        case SourceRefValidationCode.valid:
          valid += 1;
        case SourceRefValidationCode.missing:
          missing += 1;
        case SourceRefValidationCode.malformed:
          malformed += 1;
        case SourceRefValidationCode.canonicalLeakAsUpstream:
          canonicalLeakAsUpstream += 1;
      }
    }
    return IdentityCoverageReport(
      schemaVersion: 1,
      dryRun: true,
      aggregate: IdentityCoverageAggregate(
        total: results.length,
        valid: valid,
        missing: missing,
        malformed: malformed,
        canonicalLeakAsUpstream: canonicalLeakAsUpstream,
      ),
      results: results,
    );
  }
}

String _redact(String raw) {
  if (raw.isEmpty) {
    return '<empty>';
  }
  if (raw.length <= 4) {
    return '<redacted>';
  }
  return '${raw.substring(0, 2)}***${raw.substring(raw.length - 2)}';
}

String _fingerprint(List<String> parts) {
  final joined = parts.join('\u0000');
  return sha256.convert(utf8.encode(joined)).toString();
}
