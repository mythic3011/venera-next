import 'package:venera/foundation/comic_type.dart';
import 'package:venera/foundation/source_ref.dart';

enum ResumeSnapshotDiagnosticCode {
  malformed,
  unsupportedVersion,
  missingRequiredField,
  sourceRefInvalid,
}

class ResumeSnapshotReadResult {
  final ResumeSnapshot? snapshot;
  final ResumeSnapshotDiagnosticCode? diagnostic;

  const ResumeSnapshotReadResult({
    required this.snapshot,
    this.diagnostic,
  });
}

class ResumeSnapshot {
  static const int version = 1;

  final ReadingResumeTarget target;
  final SourceRef sourceRef;

  const ResumeSnapshot({
    required this.target,
    required this.sourceRef,
  });

  Map<String, dynamic> toJson() {
    return {
      'version': version,
      'target': target.toJson(),
      'sourceRef': sourceRef.toJson(),
    };
  }

  factory ResumeSnapshot.fromJson(Map<String, dynamic> json) {
    final snapshotVersion = json['version'];
    if (snapshotVersion is! num) {
      throw ArgumentError('Missing required field: version');
    }
    if (snapshotVersion.toInt() != version) {
      throw UnsupportedError('Unsupported snapshot version: $snapshotVersion');
    }
    return ResumeSnapshot(
      target: ReadingResumeTarget.fromJson(
        Map<String, dynamic>.from(json['target'] as Map),
      ),
      sourceRef: SourceRef.fromJson(
        Map<String, dynamic>.from(json['sourceRef'] as Map),
      ),
    );
  }
}

class ResumeTargetStore {
  ResumeTargetStore(this._implicitData);

  static const _storeKey = 'reading_resume_targets_v1';
  final Map<String, dynamic> _implicitData;

  String _entryKey(String comicId, ComicType type) => '${type.value}:$comicId';

  Map<String, dynamic> _readStore() {
    final raw = _implicitData[_storeKey];
    if (raw is Map<String, dynamic>) {
      return raw;
    }
    if (raw is Map) {
      return Map<String, dynamic>.from(raw);
    }
    return <String, dynamic>{};
  }

  ResumeSnapshotReadResult readWithDiagnostic(String comicId, ComicType type) {
    final store = _readStore();
    final raw = store[_entryKey(comicId, type)];
    if (raw is! Map) {
      return const ResumeSnapshotReadResult(snapshot: null);
    }
    try {
      final snapshot = ResumeSnapshot.fromJson(Map<String, dynamic>.from(raw));
      return ResumeSnapshotReadResult(snapshot: snapshot);
    } on UnsupportedError {
      return const ResumeSnapshotReadResult(
        snapshot: null,
        diagnostic: ResumeSnapshotDiagnosticCode.unsupportedVersion,
      );
    } on ArgumentError {
      return const ResumeSnapshotReadResult(
        snapshot: null,
        diagnostic: ResumeSnapshotDiagnosticCode.missingRequiredField,
      );
    } on TypeError {
      return const ResumeSnapshotReadResult(
        snapshot: null,
        diagnostic: ResumeSnapshotDiagnosticCode.sourceRefInvalid,
      );
    } catch (_) {
      return const ResumeSnapshotReadResult(
        snapshot: null,
        diagnostic: ResumeSnapshotDiagnosticCode.malformed,
      );
    }
  }

  ResumeSnapshot? read(String comicId, ComicType type) {
    return readWithDiagnostic(comicId, type).snapshot;
  }

  void write({
    required String comicId,
    required ComicType type,
    required int chapter,
    required int? group,
    required int page,
    required SourceRef sourceRef,
  }) {
    final store = _readStore();
    final chapterEntryId = group == null ? '$chapter' : '$group-$chapter';
    final snapshot = ResumeSnapshot(
      target: ReadingResumeTarget(
        seriesId: comicId,
        chapterEntryId: chapterEntryId,
        sourceRefId: sourceRef.id,
        sourceRefType: sourceRef.type,
        sourceKey: sourceRef.sourceKey,
        pageIndex: page,
        updatedAt: DateTime.now(),
      ),
      sourceRef: sourceRef,
    );
    store[_entryKey(comicId, type)] = snapshot.toJson();
    _implicitData[_storeKey] = store;
  }
}
