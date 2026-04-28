class LocalChapterGroup {
  final String id;
  final String label;
  final int sortOrder;

  const LocalChapterGroup({
    required this.id,
    required this.label,
    required this.sortOrder,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'sortOrder': sortOrder,
  };

  factory LocalChapterGroup.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final label = json['label'];
    final sortOrder = json['sortOrder'];
    if (id is! String || label is! String || sortOrder is! int) {
      throw const FormatException('Invalid LocalChapterGroup');
    }
    return LocalChapterGroup(id: id, label: label, sortOrder: sortOrder);
  }
}

class LocalChapterMeta {
  final String chapterId;
  final String? displayTitle;
  final String? groupId;
  final int? sortOrder;

  const LocalChapterMeta({
    required this.chapterId,
    this.displayTitle,
    this.groupId,
    this.sortOrder,
  });

  Map<String, dynamic> toJson() => {
    'chapterId': chapterId,
    if (displayTitle != null) 'displayTitle': displayTitle,
    if (groupId != null) 'groupId': groupId,
    if (sortOrder != null) 'sortOrder': sortOrder,
  };

  factory LocalChapterMeta.fromJson(Map<String, dynamic> json) {
    final chapterId = json['chapterId'];
    final displayTitle = json['displayTitle'];
    final groupId = json['groupId'];
    final sortOrder = json['sortOrder'];
    if (chapterId is! String) {
      throw const FormatException('Invalid LocalChapterMeta chapterId');
    }
    if (displayTitle != null && displayTitle is! String) {
      throw const FormatException('Invalid LocalChapterMeta displayTitle');
    }
    if (groupId != null && groupId is! String) {
      throw const FormatException('Invalid LocalChapterMeta groupId');
    }
    if (sortOrder != null && sortOrder is! int) {
      throw const FormatException('Invalid LocalChapterMeta sortOrder');
    }
    return LocalChapterMeta(
      chapterId: chapterId,
      displayTitle: displayTitle,
      groupId: groupId,
      sortOrder: sortOrder,
    );
  }
}

class LocalSeriesMeta {
  final String seriesKey;
  final String? displayTitle;
  final List<LocalChapterGroup> groups;
  final Map<String, LocalChapterMeta> chapters;

  const LocalSeriesMeta({
    required this.seriesKey,
    this.displayTitle,
    required this.groups,
    required this.chapters,
  });

  static const defaultGroupId = 'default';
  static const legacyDefaultGroupId = '__default__';
  static const defaultGroupLabel = 'Chapters';

  Map<String, dynamic> toJson() => {
    'seriesKey': seriesKey,
    if (displayTitle != null) 'displayTitle': displayTitle,
    'groups': groups.map((e) => e.toJson()).toList(growable: false),
    'chapters': chapters.map((k, v) => MapEntry(k, v.toJson())),
  };

  factory LocalSeriesMeta.fromJson(Map<String, dynamic> json) {
    final seriesKey = json['seriesKey'];
    final displayTitle = json['displayTitle'];
    if (seriesKey is! String) {
      throw const FormatException('Invalid LocalSeriesMeta seriesKey');
    }
    if (displayTitle != null && displayTitle is! String) {
      throw const FormatException('Invalid LocalSeriesMeta displayTitle');
    }

    final groups = <LocalChapterGroup>[];
    final groupsRaw = json['groups'];
    if (groupsRaw is List) {
      for (final item in groupsRaw) {
        if (item is! Map<String, dynamic>) {
          throw const FormatException('Invalid LocalSeriesMeta groups');
        }
        groups.add(LocalChapterGroup.fromJson(item));
      }
    }

    final chapters = <String, LocalChapterMeta>{};
    final chaptersRaw = json['chapters'];
    if (chaptersRaw is Map) {
      for (final entry in chaptersRaw.entries) {
        if (entry.key is! String || entry.value is! Map<String, dynamic>) {
          throw const FormatException('Invalid LocalSeriesMeta chapters');
        }
        chapters[entry.key as String] = LocalChapterMeta.fromJson(
          entry.value as Map<String, dynamic>,
        );
      }
    }

    return LocalSeriesMeta(
      seriesKey: seriesKey,
      displayTitle: displayTitle,
      groups: groups,
      chapters: chapters,
    );
  }

  LocalSeriesMeta copyWith({
    String? displayTitle,
    List<LocalChapterGroup>? groups,
    Map<String, LocalChapterMeta>? chapters,
  }) {
    return LocalSeriesMeta(
      seriesKey: seriesKey,
      displayTitle: displayTitle ?? this.displayTitle,
      groups: groups ?? this.groups,
      chapters: chapters ?? this.chapters,
    );
  }
}

class LocalMetadataDocument {
  final int version;
  final Map<String, LocalSeriesMeta> series;

  const LocalMetadataDocument({required this.version, required this.series});

  static const currentVersion = 1;

  Map<String, dynamic> toJson() => {
    'version': version,
    'series': series.map((k, v) => MapEntry(k, v.toJson())),
  };

  factory LocalMetadataDocument.fromJson(Map<String, dynamic> json) {
    final version = json['version'];
    if (version is! int) {
      throw const FormatException('Missing metadata version');
    }
    if (version != currentVersion) {
      throw FormatException('Unsupported metadata version: $version');
    }
    final rawSeries = json['series'];
    final series = <String, LocalSeriesMeta>{};
    if (rawSeries is Map) {
      for (final entry in rawSeries.entries) {
        if (entry.key is! String || entry.value is! Map<String, dynamic>) {
          throw const FormatException('Invalid metadata series payload');
        }
        series[entry.key as String] = LocalSeriesMeta.fromJson(
          entry.value as Map<String, dynamic>,
        );
      }
    }
    return LocalMetadataDocument(version: version, series: series);
  }

  static LocalMetadataDocument empty() {
    return const LocalMetadataDocument(
      version: currentVersion,
      series: <String, LocalSeriesMeta>{},
    );
  }
}

class EffectiveChaptersView {
  final Map<String, Map<String, String>> groupedChapters;

  const EffectiveChaptersView({required this.groupedChapters});
}
