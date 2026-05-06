import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:venera/features/reader_next/preflight/history_favorites_identity_preflight.dart';

const int m13ExpectedReportSchemaVersion = 1;

enum BackfillApplyRejectCode {
  nonDryRunReport,
  staleSchemaVersion,
  malformedCandidate,
  forbiddenValidationCode,
  forbiddenRemediationAction,
  canonicalLeakAsUpstream,
  missingFavoritesFolderName,
  backupIdMismatch,
  artifactHashMismatch,
}

class BackfillApplyRejected implements Exception {
  const BackfillApplyRejected(this.code, this.message);

  final BackfillApplyRejectCode code;
  final String message;
}

class BackfillApplyCandidate {
  const BackfillApplyCandidate({
    required this.candidateId,
    required this.recordKind,
    required this.folderName,
    required this.recordId,
    required this.sourceKey,
    required this.canonicalComicId,
    required this.upstreamComicRefId,
    required this.chapterRefId,
    required this.observedIdentityFingerprint,
  });

  final String candidateId;
  final String recordKind;
  final String? folderName;
  final String recordId;
  final String sourceKey;
  final String canonicalComicId;
  final String upstreamComicRefId;
  final String chapterRefId;
  final String observedIdentityFingerprint;

  Map<String, Object?> toCanonicalJson() {
    return <String, Object?>{
      'candidateId': candidateId,
      'recordKind': recordKind,
      'folderName': folderName ?? '',
      'recordId': recordId,
      'sourceKey': sourceKey,
      'canonicalComicId': canonicalComicId,
      'upstreamComicRefId': upstreamComicRefId,
      'chapterRefId': chapterRefId,
      'observedIdentityFingerprint': observedIdentityFingerprint,
    };
  }
}

class BackfillCheckpoint {
  const BackfillCheckpoint({
    this.lastAppliedCandidateId,
    this.appliedCandidateIds = const <String>{},
  });

  final String? lastAppliedCandidateId;
  final Set<String> appliedCandidateIds;

  BackfillCheckpoint withApplied(String candidateId) {
    final next = Set<String>.from(appliedCandidateIds)..add(candidateId);
    return BackfillCheckpoint(
      lastAppliedCandidateId: candidateId,
      appliedCandidateIds: next,
    );
  }
}

class BackfillApplyPlan {
  const BackfillApplyPlan({
    required this.reportSchemaVersion,
    required this.dryRunArtifactHash,
    required this.backupId,
    required this.candidates,
    this.checkpoint = const BackfillCheckpoint(),
  });

  final int reportSchemaVersion;
  final String dryRunArtifactHash;
  final String backupId;
  final List<BackfillApplyCandidate> candidates;
  final BackfillCheckpoint checkpoint;

  Map<String, Object?> toCanonicalJson() {
    final sorted = [...candidates]
      ..sort((a, b) => a.candidateId.compareTo(b.candidateId));
    return <String, Object?>{
      'reportSchemaVersion': reportSchemaVersion,
      'dryRunArtifactHash': dryRunArtifactHash,
      'backupId': backupId,
      'candidates': sorted
          .map((e) => e.toCanonicalJson())
          .toList(growable: false),
    };
  }
}

class BackfillApplyPlanBuilder {
  const BackfillApplyPlanBuilder();

  BackfillApplyPlan fromReport({
    required IdentityCoverageReport report,
    required String backupId,
  }) {
    if (!report.dryRun) {
      throw const BackfillApplyRejected(
        BackfillApplyRejectCode.nonDryRunReport,
        'M13 apply accepts dry-run report only.',
      );
    }
    if (report.schemaVersion != m13ExpectedReportSchemaVersion) {
      throw BackfillApplyRejected(
        BackfillApplyRejectCode.staleSchemaVersion,
        'Unexpected report schemaVersion=${report.schemaVersion}.',
      );
    }
    final candidates = <BackfillApplyCandidate>[];
    for (final row in report.results) {
      if (row.sourceRefValidationCode != SourceRefValidationCode.valid) {
        continue;
      }
      if (row.remediationAction !=
          RemediationAction.eligibleForFutureExplicitBackfill) {
        continue;
      }
      final canonicalComicId = row.explicitCanonicalComicId;
      final upstreamComicRefId = row.explicitUpstreamComicRefId;
      final chapterRefId = row.explicitChapterRefId;
      final observedFingerprint = row.observedIdentityFingerprint;
      if (canonicalComicId == null ||
          upstreamComicRefId == null ||
          chapterRefId == null ||
          observedFingerprint == null ||
          canonicalComicId.isEmpty ||
          upstreamComicRefId.isEmpty) {
        throw BackfillApplyRejected(
          BackfillApplyRejectCode.malformedCandidate,
          'Candidate missing explicit identity fields for ${row.recordId}',
        );
      }
      if (upstreamComicRefId.startsWith('remote:')) {
        throw BackfillApplyRejected(
          BackfillApplyRejectCode.canonicalLeakAsUpstream,
          'upstreamComicRefId must not be canonical: $upstreamComicRefId',
        );
      }
      if (row.kind == IdentityRecordKind.favorite &&
          (row.folderName == null || row.folderName!.isEmpty)) {
        throw BackfillApplyRejected(
          BackfillApplyRejectCode.missingFavoritesFolderName,
          'favorites candidate requires folderName for ${row.recordId}',
        );
      }
      candidates.add(
        BackfillApplyCandidate(
          candidateId: _candidateId(
            recordKind: row.kind == IdentityRecordKind.history
                ? 'history'
                : 'favorite',
            folderName: row.folderName,
            recordId: row.recordId,
            sourceKey: row.sourceKey,
            canonicalComicId: canonicalComicId,
            upstreamComicRefId: upstreamComicRefId,
            chapterRefId: chapterRefId,
          ),
          recordKind: row.kind == IdentityRecordKind.history
              ? 'history'
              : 'favorite',
          folderName: row.folderName,
          recordId: row.recordId,
          sourceKey: row.sourceKey,
          canonicalComicId: canonicalComicId,
          upstreamComicRefId: upstreamComicRefId,
          chapterRefId: chapterRefId,
          observedIdentityFingerprint: observedFingerprint,
        ),
      );
    }
    candidates.sort((a, b) => a.candidateId.compareTo(b.candidateId));
    return BackfillApplyPlan(
      reportSchemaVersion: report.schemaVersion,
      dryRunArtifactHash: canonicalDryRunArtifactHash(report),
      backupId: backupId,
      candidates: candidates,
    );
  }
}

String canonicalDryRunArtifactHash(IdentityCoverageReport report) {
  final sortedResults =
      report.results.map((entry) => entry.toJson()).toList(growable: false)
        ..sort((a, b) => _reportRowKey(a).compareTo(_reportRowKey(b)));
  final canonicalInput = <String, Object?>{
    'schemaVersion': report.schemaVersion,
    'dryRun': report.dryRun,
    'aggregate': report.aggregate.toJson(),
    'results': sortedResults,
  };
  final canonical = _canonicalizeJson(canonicalInput);
  return sha256.convert(utf8.encode(canonical)).toString();
}

String _reportRowKey(Map<String, Object?> row) {
  return [
    row['recordKind']?.toString() ?? '',
    row['sourceKey']?.toString() ?? '',
    row['recordId']?.toString() ?? '',
    row['folderName']?.toString() ?? '',
    row['explicitCanonicalComicId']?.toString() ?? '',
    row['explicitUpstreamComicRefId']?.toString() ?? '',
    row['explicitChapterRefId']?.toString() ?? '',
  ].join('\u0000');
}

String _candidateId({
  required String recordKind,
  required String? folderName,
  required String recordId,
  required String sourceKey,
  required String canonicalComicId,
  required String upstreamComicRefId,
  required String chapterRefId,
}) {
  final value = [
    recordKind,
    folderName ?? '',
    recordId,
    sourceKey,
    canonicalComicId,
    upstreamComicRefId,
    chapterRefId,
  ].join('\u0000');
  return sha256.convert(utf8.encode(value)).toString();
}

String _canonicalizeJson(Object? value) {
  Object? normalize(Object? node) {
    if (node is Map) {
      final entries = node.entries.toList()
        ..sort((a, b) => a.key.toString().compareTo(b.key.toString()));
      return Map<String, Object?>.fromEntries(
        entries.map(
          (entry) => MapEntry(entry.key.toString(), normalize(entry.value)),
        ),
      );
    }
    if (node is List) {
      return node.map(normalize).toList(growable: false);
    }
    return node;
  }

  return jsonEncode(normalize(value));
}

enum BackfillApplyWriteStatus { applied, skippedStaleRow, skippedMissingRow }

class BackfillApplyWriteResult {
  const BackfillApplyWriteResult({
    required this.status,
    required this.code,
    this.message,
  });

  final BackfillApplyWriteStatus status;
  final String code;
  final String? message;
}

abstract class BackfillApplySink {
  Future<BackfillApplyWriteResult> compareAndSet(
    BackfillApplyCandidate candidate,
  );

  Future<String?> currentFingerprint(BackfillApplyCandidate candidate);

  Future<InMemoryBackfillApplySinkRow?> readCurrentRowSnapshot(
    BackfillApplyCandidate candidate,
  );
}

class InMemoryBackfillApplySinkRow {
  InMemoryBackfillApplySinkRow({
    required this.recordKind,
    required this.folderName,
    required this.recordId,
    required this.sourceKey,
    required this.canonicalComicId,
    required this.upstreamComicRefId,
    required this.chapterRefId,
  });

  final String recordKind;
  final String? folderName;
  final String recordId;
  final String sourceKey;
  String canonicalComicId;
  String upstreamComicRefId;
  String chapterRefId;

  String get fingerprint => sha256
      .convert(
        utf8.encode(
          [
            recordKind,
            folderName ?? '',
            recordId,
            sourceKey,
            canonicalComicId,
            upstreamComicRefId,
            chapterRefId,
          ].join('\u0000'),
        ),
      )
      .toString();
}

class InMemoryBackfillApplySink implements BackfillApplySink {
  final Map<String, InMemoryBackfillApplySinkRow> _rows = {};

  static String rowKey({
    required String recordKind,
    required String? folderName,
    required String recordId,
    required String sourceKey,
  }) {
    return [recordKind, folderName ?? '', recordId, sourceKey].join('\u0000');
  }

  void seed(InMemoryBackfillApplySinkRow row) {
    _rows[rowKey(
          recordKind: row.recordKind,
          folderName: row.folderName,
          recordId: row.recordId,
          sourceKey: row.sourceKey,
        )] =
        row;
  }

  void mutateRowForTest({
    required String recordKind,
    required String? folderName,
    required String recordId,
    required String sourceKey,
    required String canonicalComicId,
    required String upstreamComicRefId,
    required String chapterRefId,
  }) {
    final key = rowKey(
      recordKind: recordKind,
      folderName: folderName,
      recordId: recordId,
      sourceKey: sourceKey,
    );
    final row = _rows[key];
    if (row == null) {
      return;
    }
    row
      ..canonicalComicId = canonicalComicId
      ..upstreamComicRefId = upstreamComicRefId
      ..chapterRefId = chapterRefId;
  }

  @override
  Future<BackfillApplyWriteResult> compareAndSet(
    BackfillApplyCandidate candidate,
  ) async {
    final key = rowKey(
      recordKind: candidate.recordKind,
      folderName: candidate.folderName,
      recordId: candidate.recordId,
      sourceKey: candidate.sourceKey,
    );
    final row = _rows[key];
    if (row == null) {
      return const BackfillApplyWriteResult(
        status: BackfillApplyWriteStatus.skippedMissingRow,
        code: 'MISSING_ROW',
      );
    }
    if (row.fingerprint != candidate.observedIdentityFingerprint) {
      return const BackfillApplyWriteResult(
        status: BackfillApplyWriteStatus.skippedStaleRow,
        code: 'STALE_ROW',
      );
    }
    row
      ..canonicalComicId = candidate.canonicalComicId
      ..upstreamComicRefId = candidate.upstreamComicRefId
      ..chapterRefId = candidate.chapterRefId;
    return const BackfillApplyWriteResult(
      status: BackfillApplyWriteStatus.applied,
      code: 'APPLIED',
    );
  }

  @override
  Future<String?> currentFingerprint(BackfillApplyCandidate candidate) async {
    final row =
        _rows[rowKey(
          recordKind: candidate.recordKind,
          folderName: candidate.folderName,
          recordId: candidate.recordId,
          sourceKey: candidate.sourceKey,
        )];
    return row?.fingerprint;
  }

  @override
  Future<InMemoryBackfillApplySinkRow?> readCurrentRowSnapshot(
    BackfillApplyCandidate candidate,
  ) async {
    final row =
        _rows[rowKey(
          recordKind: candidate.recordKind,
          folderName: candidate.folderName,
          recordId: candidate.recordId,
          sourceKey: candidate.sourceKey,
        )];
    return row;
  }
}

class BackfillApplyExecutionResult {
  const BackfillApplyExecutionResult({
    required this.appliedCount,
    required this.skippedStaleRowCount,
    required this.skippedMissingRowCount,
    required this.checkpoint,
    required this.diagnostics,
  });

  final int appliedCount;
  final int skippedStaleRowCount;
  final int skippedMissingRowCount;
  final BackfillCheckpoint checkpoint;
  final List<Map<String, String>> diagnostics;
}

class BackfillApplyExecutionService {
  const BackfillApplyExecutionService();

  Future<BackfillApplyExecutionResult> execute({
    required BackfillApplyPlan plan,
    required IdentityCoverageReport report,
    required BackfillApplySink sink,
    BackfillCheckpoint checkpoint = const BackfillCheckpoint(),
    required String backupId,
  }) async {
    if (backupId != plan.backupId) {
      throw const BackfillApplyRejected(
        BackfillApplyRejectCode.backupIdMismatch,
        'backupId mismatch',
      );
    }
    final recomputedHash = canonicalDryRunArtifactHash(report);
    if (recomputedHash != plan.dryRunArtifactHash) {
      throw const BackfillApplyRejected(
        BackfillApplyRejectCode.artifactHashMismatch,
        'dryRunArtifactHash mismatch',
      );
    }

    var appliedCount = 0;
    var skippedStaleRowCount = 0;
    var skippedMissingRowCount = 0;
    var nextCheckpoint = checkpoint;
    final diagnostics = <Map<String, String>>[];

    final orderedCandidates = [...plan.candidates]
      ..sort((a, b) => a.candidateId.compareTo(b.candidateId));
    for (final candidate in orderedCandidates) {
      if (nextCheckpoint.appliedCandidateIds.contains(candidate.candidateId)) {
        continue;
      }
      final result = await sink.compareAndSet(candidate);
      switch (result.status) {
        case BackfillApplyWriteStatus.applied:
          appliedCount += 1;
          nextCheckpoint = nextCheckpoint.withApplied(candidate.candidateId);
        case BackfillApplyWriteStatus.skippedStaleRow:
          skippedStaleRowCount += 1;
          diagnostics.add(<String, String>{
            'candidateId': candidate.candidateId,
            'code': result.code,
          });
        case BackfillApplyWriteStatus.skippedMissingRow:
          skippedMissingRowCount += 1;
          diagnostics.add(<String, String>{
            'candidateId': candidate.candidateId,
            'code': result.code,
          });
      }
    }
    return BackfillApplyExecutionResult(
      appliedCount: appliedCount,
      skippedStaleRowCount: skippedStaleRowCount,
      skippedMissingRowCount: skippedMissingRowCount,
      checkpoint: nextCheckpoint,
      diagnostics: diagnostics,
    );
  }
}

class BackfillPostApplyVerifierResult {
  const BackfillPostApplyVerifierResult({
    required this.validAppliedCount,
    required this.invalidAppliedCount,
  });

  final int validAppliedCount;
  final int invalidAppliedCount;
}

class BackfillPostApplyVerifier {
  const BackfillPostApplyVerifier();

  Future<BackfillPostApplyVerifierResult> verify({
    required BackfillApplyPlan plan,
    required BackfillCheckpoint checkpoint,
    required BackfillApplySink sink,
  }) async {
    var valid = 0;
    var invalid = 0;
    final orderedCandidates = [...plan.candidates]
      ..sort((a, b) => a.candidateId.compareTo(b.candidateId));
    const scanner = HistoryFavoritesIdentityCoverageScanner();
    for (final candidate in orderedCandidates) {
      if (!checkpoint.appliedCandidateIds.contains(candidate.candidateId)) {
        continue;
      }
      final current = await sink.readCurrentRowSnapshot(candidate);
      if (current == null) {
        invalid += 1;
        continue;
      }
      final input = candidate.recordKind == 'favorite'
          ? IdentityCoverageInput.favorite(
              recordId: current.recordId,
              sourceKey: current.sourceKey,
              folderName: current.folderName,
              sourceRef: ExplicitSourceRefSnapshot(
                sourceKey: current.sourceKey,
                upstreamComicRefId: current.upstreamComicRefId,
                chapterRefId: current.chapterRefId,
              ),
              explicitSnapshotAlreadyPersisted: true,
            )
          : IdentityCoverageInput.history(
              recordId: current.recordId,
              sourceKey: current.sourceKey,
              folderName: current.folderName,
              sourceRef: ExplicitSourceRefSnapshot(
                sourceKey: current.sourceKey,
                upstreamComicRefId: current.upstreamComicRefId,
                chapterRefId: current.chapterRefId,
              ),
              explicitSnapshotAlreadyPersisted: true,
            );
      final scan = scanner.scan(input);
      if (scan.sourceRefValidationCode == SourceRefValidationCode.valid) {
        valid += 1;
      } else {
        invalid += 1;
      }
    }
    return BackfillPostApplyVerifierResult(
      validAppliedCount: valid,
      invalidAppliedCount: invalid,
    );
  }
}
