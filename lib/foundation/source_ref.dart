enum SourceRefType {
  local,
  remote,
}

extension SourceRefTypeX on SourceRefType {
  String get key => switch (this) {
    SourceRefType.local => 'local',
    SourceRefType.remote => 'remote',
  };

  static SourceRefType fromKey(String key) {
    return switch (key) {
      'local' => SourceRefType.local,
      'remote' => SourceRefType.remote,
      _ => throw ArgumentError('Unknown SourceRefType: $key'),
    };
  }
}

class SourceRef {
  final String id;
  final SourceRefType type;
  final String sourceKey;
  final String refId;
  final String? routeKey;
  final Map<String, Object?> params;

  const SourceRef({
    required this.id,
    required this.type,
    required this.sourceKey,
    required this.refId,
    this.routeKey,
    this.params = const {},
  });

  static String _chapterToken(String? chapterId) => chapterId ?? '_';

  factory SourceRef.fromLegacyLocal({
    required String localType,
    required String localComicId,
    String? chapterId,
  }) {
    return SourceRef(
      id: 'local:$localType:$localComicId:${_chapterToken(chapterId)}',
      type: SourceRefType.local,
      sourceKey: 'local',
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
      refId: comicId,
      routeKey: routeKey,
      params: {
        'comicId': comicId,
        'chapterId': chapterId,
      },
    );
  }

  factory SourceRef.fromLegacy({
    required String comicId,
    required String sourceKey,
    String? chapterId,
  }) {
    if (sourceKey == 'local') {
      return SourceRef.fromLegacyLocal(
        localType: 'local',
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
      'refId': refId,
      'routeKey': routeKey,
      'params': params,
    };
  }

  factory SourceRef.fromJson(Map<String, dynamic> json) {
    final id = _requireString(json, 'id');
    final type = SourceRefTypeX.fromKey(_requireString(json, 'type'));
    final sourceKey = _requireString(json, 'sourceKey');
    final refId = _requireString(json, 'refId');
    final rawParams = json['params'];
    return SourceRef(
      id: id,
      type: type,
      sourceKey: sourceKey,
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
  final int pageIndex;
  final DateTime updatedAt;

  const ReadingResumeTarget({
    required this.seriesId,
    required this.chapterEntryId,
    required this.sourceRefId,
    required this.sourceRefType,
    required this.sourceKey,
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
      pageIndex: requireInt('pageIndex'),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        requireInt('updatedAtMs'),
      ),
    );
  }
}
