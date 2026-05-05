import 'package:venera/foundation/sources/identity/source_identity.dart';

enum SourceRefType { local, remote }

String sourceRefTypeKey(SourceRefType type) => switch (type) {
  SourceRefType.local => localSourceRefTypeKey,
  SourceRefType.remote => remoteSourceRefTypeKey,
};

SourceRefType sourceRefTypeFromKey(String key) {
  return switch (key) {
    localSourceRefTypeKey => SourceRefType.local,
    remoteSourceRefTypeKey => SourceRefType.remote,
    _ => throw ArgumentError('Unknown SourceRefType: $key'),
  };
}

extension SourceRefTypeX on SourceRefType {
  String get key => sourceRefTypeKey(this);

  static SourceRefType fromKey(String key) => sourceRefTypeFromKey(key);
}

enum SourceIdentityErrorCode {
  missingSourceKey,
  missingRefId,
  invalidRefId,
  nonCanonicalRouteKeyLeak,
}

class SourceIdentityError implements Exception {
  const SourceIdentityError(this.code, {required this.message});

  final SourceIdentityErrorCode code;
  final String message;

  String get codeKey => switch (code) {
    SourceIdentityErrorCode.missingSourceKey => 'missingSourceKey',
    SourceIdentityErrorCode.missingRefId => 'missingRefId',
    SourceIdentityErrorCode.invalidRefId => 'invalidRefId',
    SourceIdentityErrorCode.nonCanonicalRouteKeyLeak =>
      'nonCanonicalRouteKeyLeak',
  };

  @override
  String toString() => 'SourceIdentityError($codeKey): $message';
}

class SourceIdentityPolicy {
  const SourceIdentityPolicy._();

  static void assertAdapterSafe(SourceRef ref) {
    if (ref.sourceKey.trim().isEmpty) {
      throw const SourceIdentityError(
        SourceIdentityErrorCode.missingSourceKey,
        message: 'SourceRef.sourceKey is required.',
      );
    }
    if (ref.refId.trim().isEmpty) {
      throw const SourceIdentityError(
        SourceIdentityErrorCode.missingRefId,
        message: 'SourceRef.refId is required.',
      );
    }
    if (ref.type == SourceRefType.remote) {
      if (ref.refId.startsWith('remote:')) {
        throw const SourceIdentityError(
          SourceIdentityErrorCode.nonCanonicalRouteKeyLeak,
          message: 'Remote adapter refId must be upstream ID, not canonical ID.',
        );
      }
      if (ref.refId.contains(':')) {
        throw const SourceIdentityError(
          SourceIdentityErrorCode.invalidRefId,
          message: 'Remote adapter refId must not contain route delimiters.',
        );
      }
    }
  }
}

class SourceRef {
  final String id;
  final SourceRefType type;
  final String sourceKey;
  final SourceIdentity sourceIdentity;
  final String refId;
  final String? routeKey;
  final Map<String, Object?> params;

  const SourceRef({
    required this.id,
    required this.type,
    required this.sourceKey,
    required this.sourceIdentity,
    required this.refId,
    this.routeKey,
    this.params = const {},
  });

  static String _chapterToken(String? chapterId) => chapterId ?? '_';

  String get canonicalId => switch (type) {
    SourceRefType.local => refId,
    SourceRefType.remote => 'remote:$sourceKey:$refId',
  };

  factory SourceRef.fromLegacyLocal({
    required String localType,
    required String localComicId,
    String? chapterId,
  }) {
    return SourceRef(
      id: 'local:$localType:$localComicId:${_chapterToken(chapterId)}',
      type: SourceRefType.local,
      sourceKey: localSourceKey,
      sourceIdentity: sourceIdentityFromKey(
        localSourceKey,
        names: const ['Local'],
      ),
      refId: localComicId,
      params: {
        'localType': localType,
        'localComicId': localComicId,
        'chapterId': chapterId,
      },
    );
  }

  factory SourceRef.fromLegacyRemote({
    required String sourceKey,
    required String comicId,
    String? chapterId,
    String? routeKey,
  }) {
    return SourceRef(
      id: 'remote:$sourceKey:$comicId:${_chapterToken(chapterId)}',
      type: SourceRefType.remote,
      sourceKey: sourceKey,
      sourceIdentity: sourceIdentityFromKey(sourceKey),
      refId: comicId,
      routeKey: routeKey,
      params: {'comicId': comicId, 'chapterId': chapterId},
    );
  }

  factory SourceRef.fromLegacy({
    required String comicId,
    required String sourceKey,
    String? chapterId,
  }) {
    if (isLocalSourceKey(sourceKey)) {
      return SourceRef.fromLegacyLocal(
        localType: localSourceKey,
        localComicId: comicId,
        chapterId: chapterId,
      );
    }
    return SourceRef.fromLegacyRemote(
      sourceKey: sourceKey,
      comicId: comicId,
      chapterId: chapterId,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.key,
      'sourceKey': sourceKey,
      'sourceIdentity': sourceIdentity.toJson(),
      'refId': refId,
      'routeKey': routeKey,
      'params': params,
    };
  }

  factory SourceRef.fromJson(Map<String, dynamic> json) {
    final id = _requireString(json, 'id');
    final type = SourceRefTypeX.fromKey(_requireString(json, 'type'));
    final sourceKey = _requireString(json, 'sourceKey');
    final rawIdentity = json['sourceIdentity'];
    final refId = _requireString(json, 'refId');
    final rawParams = json['params'];
    return SourceRef(
      id: id,
      type: type,
      sourceKey: sourceKey,
      sourceIdentity: rawIdentity is Map<String, dynamic>
          ? SourceIdentity.fromJson(rawIdentity)
          : sourceIdentityFromKey(
              sourceKey,
              names: type == SourceRefType.local ? const ['Local'] : const [],
            ),
      refId: refId,
      routeKey: json['routeKey'] as String?,
      params: rawParams is Map<String, dynamic>
          ? Map<String, Object?>.from(rawParams)
          : const <String, Object?>{},
    );
  }

  static String _requireString(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is! String || value.isEmpty) {
      throw ArgumentError('Missing required field: $key');
    }
    return value;
  }
}

class ReadingResumeTarget {
  final String seriesId;
  final String chapterEntryId;
  final String sourceRefId;
  final SourceRefType sourceRefType;
  final String sourceKey;
  final SourceIdentity? sourceIdentity;
  final int pageIndex;
  final DateTime updatedAt;

  const ReadingResumeTarget({
    required this.seriesId,
    required this.chapterEntryId,
    required this.sourceRefId,
    required this.sourceRefType,
    required this.sourceKey,
    this.sourceIdentity,
    required this.pageIndex,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'seriesId': seriesId,
      'chapterEntryId': chapterEntryId,
      'sourceRefId': sourceRefId,
      'sourceRefType': sourceRefType.key,
      'sourceKey': sourceKey,
      'sourceIdentity': sourceIdentity?.toJson(),
      'pageIndex': pageIndex,
      'updatedAtMs': updatedAt.millisecondsSinceEpoch,
    };
  }

  factory ReadingResumeTarget.fromJson(Map<String, dynamic> json) {
    String requireString(String key) {
      final value = json[key];
      if (value is! String || value.isEmpty) {
        throw ArgumentError('Missing required field: $key');
      }
      return value;
    }

    int requireInt(String key) {
      final value = json[key];
      if (value is! num) {
        throw ArgumentError('Missing required field: $key');
      }
      return value.toInt();
    }

    return ReadingResumeTarget(
      seriesId: requireString('seriesId'),
      chapterEntryId: requireString('chapterEntryId'),
      sourceRefId: requireString('sourceRefId'),
      sourceRefType: SourceRefTypeX.fromKey(requireString('sourceRefType')),
      sourceKey: requireString('sourceKey'),
      sourceIdentity: json['sourceIdentity'] is Map<String, dynamic>
          ? SourceIdentity.fromJson(
              Map<String, dynamic>.from(json['sourceIdentity']),
            )
          : null,
      pageIndex: requireInt('pageIndex'),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(requireInt('updatedAtMs')),
    );
  }
}
