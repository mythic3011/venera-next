part of 'comic_source.dart';

abstract final class _ModelJsonKey {
  static const userName = 'userName';
  static const avatar = 'avatar';
  static const content = 'content';
  static const time = 'time';
  static const replyCount = 'replyCount';
  static const id = 'id';
  static const score = 'score';
  static const isLiked = 'isLiked';
  static const voteStatus = 'voteStatus';
  static const title = 'title';
  static const subtitle = 'subtitle';
  static const subTitle = 'subTitle';
  static const cover = 'cover';
  static const tags = 'tags';
  static const description = 'description';
  static const sourceKey = 'sourceKey';
  static const maxPage = 'maxPage';
  static const language = 'language';
  static const favoriteId = 'favoriteId';
  static const stars = 'stars';
  static const chapters = 'chapters';
  static const comicId = 'comicId';
  static const thumbnails = 'thumbnails';
  static const recommend = 'recommend';
  static const isFavorite = 'isFavorite';
  static const subId = 'subId';
  static const likesCount = 'likesCount';
  static const commentCount = 'commentCount';
  static const uploader = 'uploader';
  static const uploadTime = 'uploadTime';
  static const updateTime = 'updateTime';
  static const url = 'url';
  static const comments = 'comments';
  static const page = 'page';
  static const action = 'action';
  static const keyword = 'keyword';
  static const attributes = 'attributes';
  static const options = 'options';
  static const category = 'category';
  static const param = 'param';
  static const text = 'text';
}

const Object _copyWithSentinel = Object();

extension _ModelJsonRead on Map<String, dynamic> {
  String readString(String key, {String fallback = ''}) {
    final value = this[key];
    return value is String ? value : fallback;
  }

  String? readStringOrNull(String key) {
    final value = this[key];
    return value is String ? value : null;
  }

  int? readIntOrNull(String key) {
    final value = this[key];
    if (value is int) return value;
    if (value is num) return value.toInt();
    return null;
  }

  bool? readBoolOrNull(String key) {
    final value = this[key];
    return value is bool ? value : null;
  }

  List<String>? readStringListOrNull(String key) {
    final value = this[key];
    if (value is! List) return null;
    return value.whereType<String>().toList();
  }
}

class Comment {
  final String userName;
  final String? avatar;
  final String content;
  final String? time;
  final int? replyCount;
  final String? id;
  int? score;
  final bool? isLiked;
  int? voteStatus; // 1: upvote, -1: downvote, 0: none

  static String? parseTime(dynamic value) {
    if (value == null) return null;
    if (value is int) {
      if (value < 10000000000) {
        return DateTime.fromMillisecondsSinceEpoch(
          value * 1000,
        ).toString().substring(0, 19);
      } else {
        return DateTime.fromMillisecondsSinceEpoch(
          value,
        ).toString().substring(0, 19);
      }
    }
    return value.toString();
  }

  Comment.fromJson(Map<String, dynamic> json)
    : userName = json.readString(_ModelJsonKey.userName),
      avatar = json.readStringOrNull(_ModelJsonKey.avatar),
      content = json.readString(_ModelJsonKey.content),
      time = parseTime(json[_ModelJsonKey.time]),
      replyCount = json.readIntOrNull(_ModelJsonKey.replyCount),
      id = json[_ModelJsonKey.id]?.toString(),
      score = json.readIntOrNull(_ModelJsonKey.score),
      isLiked = json.readBoolOrNull(_ModelJsonKey.isLiked),
      voteStatus = json.readIntOrNull(_ModelJsonKey.voteStatus);
}

class Comic {
  final String title;

  final String cover;

  final String id;

  final String? subtitle;

  final List<String>? tags;

  final String description;

  final String sourceKey;

  final int? maxPage;

  final String? language;

  final String? favoriteId;

  /// 0-5
  final double? stars;

  const Comic(
    this.title,
    this.cover,
    this.id,
    this.subtitle,
    this.tags,
    this.description,
    this.sourceKey,
    this.maxPage,
    this.language,
  ) : favoriteId = null,
      stars = null;

  Map<String, dynamic> toJson() {
    return {
      "title": title,
      "cover": cover,
      "id": id,
      "subTitle": subtitle,
      "tags": tags,
      "description": description,
      "sourceKey": sourceKey,
      "maxPage": maxPage,
      "language": language,
      "favoriteId": favoriteId,
    };
  }

  Comic.fromJson(Map<String, dynamic> json, this.sourceKey)
    : title = json.readString(_ModelJsonKey.title),
      subtitle =
          json.readStringOrNull(_ModelJsonKey.subtitle) ??
          json.readStringOrNull(_ModelJsonKey.subTitle) ??
          "",
      cover = json.readString(_ModelJsonKey.cover),
      id = json.readString(_ModelJsonKey.id),
      tags = json.readStringListOrNull(_ModelJsonKey.tags) ?? const <String>[],
      description = json.readString(_ModelJsonKey.description),
      maxPage = json.readIntOrNull(_ModelJsonKey.maxPage),
      language = json.readStringOrNull(_ModelJsonKey.language),
      favoriteId = json.readStringOrNull(_ModelJsonKey.favoriteId),
      stars = (json[_ModelJsonKey.stars] as num?)?.toDouble();

  @override
  bool operator ==(Object other) {
    if (other is! Comic) return false;
    return other.id == id && other.sourceKey == sourceKey;
  }

  @override
  int get hashCode => id.hashCode ^ sourceKey.hashCode;

  @override
  toString() => "$sourceKey@$id";
}

class ComicID {
  final SourceComicId sourceComicId;

  ComicID(this.type, this.id)
    : sourceComicId = SourceComicId.fromComicType(type, id);

  factory ComicID.fromSourceKey(String sourceKey, String id) {
    return ComicID(ComicType(sourceTypeValueFromKey(sourceKey)), id);
  }

  final ComicType type;

  final String id;

  String get sourceKey => sourceComicId.sourceKey;

  @override
  bool operator ==(Object other) {
    if (other is! ComicID) return false;
    return other.sourceKey == sourceKey && other.id == id;
  }

  @override
  int get hashCode => sourceKey.hashCode ^ id.hashCode;

  @override
  String toString() => "$sourceKey@$id";
}

class SourceComicId {
  final String sourceKey;
  final String id;

  const SourceComicId({required this.sourceKey, required this.id});

  factory SourceComicId.fromComicType(ComicType type, String id) {
    return SourceComicId(sourceKey: type.sourceKey, id: id);
  }

  ComicType get comicType => ComicType(sourceTypeValueFromKey(sourceKey));

  @override
  bool operator ==(Object other) {
    if (other is! SourceComicId) return false;
    return other.sourceKey == sourceKey && other.id == id;
  }

  @override
  int get hashCode => sourceKey.hashCode ^ id.hashCode;

  @override
  String toString() => "$sourceKey@$id";
}

class ComicDetails with HistoryMixin {
  @override
  final String title;

  @override
  final String? subTitle;

  @override
  final String cover;

  final String? description;

  final Map<String, List<String>> tags;

  /// id-name
  final ComicChapters? chapters;

  final List<String>? thumbnails;

  final List<Comic>? recommend;

  final String sourceKey;

  final String comicId;

  final bool? isFavorite;

  final String? subId;

  final bool? isLiked;

  final int? likesCount;

  final int? commentCount;

  final String? uploader;

  final String? uploadTime;

  final String? updateTime;

  final String? url;

  final double? stars;

  @override
  final int? maxPage;

  final List<Comment>? comments;

  ComicDetails({
    required this.title,
    required this.subTitle,
    required this.cover,
    required this.description,
    required Map<String, List<String>> tags,
    required this.chapters,
    required this.thumbnails,
    required this.recommend,
    required this.sourceKey,
    required this.comicId,
    required this.isFavorite,
    required this.subId,
    required this.isLiked,
    required this.likesCount,
    required this.commentCount,
    required this.uploader,
    required this.uploadTime,
    required this.updateTime,
    required this.url,
    required this.stars,
    required this.maxPage,
    required this.comments,
  }) : tags = {
         for (final entry in tags.entries)
           entry.key: List<String>.from(entry.value),
       };

  static Map<String, List<String>> _generateMap(Map<dynamic, dynamic> map) {
    var res = <String, List<String>>{};
    map.forEach((key, value) {
      if (value is List) {
        res[key] = List<String>.from(value);
      }
    });
    return res;
  }

  ComicDetails.fromJson(Map<String, dynamic> json)
    : title = json.readString(_ModelJsonKey.title),
      subTitle = json.readStringOrNull(_ModelJsonKey.subtitle),
      cover = json.readString(_ModelJsonKey.cover),
      description = json.readStringOrNull(_ModelJsonKey.description),
      tags = _generateMap(
        Map<dynamic, dynamic>.from(
          json[_ModelJsonKey.tags] as Map? ?? const <String, dynamic>{},
        ),
      ),
      chapters = ComicChapters.fromJsonOrNull(json[_ModelJsonKey.chapters]),
      sourceKey = json.readString(_ModelJsonKey.sourceKey),
      comicId = json.readString(_ModelJsonKey.comicId),
      thumbnails = ListOrNull.from(json[_ModelJsonKey.thumbnails]),
      recommend = (json[_ModelJsonKey.recommend] as List?)
          ?.whereType<Map>()
          .map(
            (e) => Comic.fromJson(
              Map<String, dynamic>.from(e),
              json.readString(_ModelJsonKey.sourceKey),
            ),
          )
          .toList(),
      isFavorite = json.readBoolOrNull(_ModelJsonKey.isFavorite),
      subId = json.readStringOrNull(_ModelJsonKey.subId),
      likesCount = json.readIntOrNull(_ModelJsonKey.likesCount),
      isLiked = json.readBoolOrNull(_ModelJsonKey.isLiked),
      commentCount = json.readIntOrNull(_ModelJsonKey.commentCount),
      uploader = json.readStringOrNull(_ModelJsonKey.uploader),
      uploadTime = json.readStringOrNull(_ModelJsonKey.uploadTime),
      updateTime = json.readStringOrNull(_ModelJsonKey.updateTime),
      url = json.readStringOrNull(_ModelJsonKey.url),
      stars = (json[_ModelJsonKey.stars] as num?)?.toDouble(),
      maxPage = json.readIntOrNull(_ModelJsonKey.maxPage),
      comments = (json[_ModelJsonKey.comments] as List?)
          ?.whereType<Map>()
          .map((e) => Comment.fromJson(Map<String, dynamic>.from(e)))
          .toList();

  ComicDetails copyWith({
    String? title,
    Object? subTitle = _copyWithSentinel,
    String? cover,
    Object? description = _copyWithSentinel,
    Map<String, List<String>>? tags,
    ComicChapters? chapters,
    List<String>? thumbnails,
    List<Comic>? recommend,
    String? sourceKey,
    String? comicId,
    bool? isFavorite,
    Object? subId = _copyWithSentinel,
    bool? isLiked,
    int? likesCount,
    int? commentCount,
    Object? uploader = _copyWithSentinel,
    Object? uploadTime = _copyWithSentinel,
    Object? updateTime = _copyWithSentinel,
    Object? url = _copyWithSentinel,
    Object? stars = _copyWithSentinel,
    int? maxPage,
    Object? comments = _copyWithSentinel,
  }) {
    return ComicDetails(
      title: title ?? this.title,
      subTitle:
          identical(subTitle, _copyWithSentinel) ? this.subTitle : subTitle as String?,
      cover: cover ?? this.cover,
      description:
          identical(description, _copyWithSentinel)
              ? this.description
              : description as String?,
      tags: tags ?? this.tags,
      chapters: chapters ?? this.chapters,
      thumbnails: thumbnails ?? this.thumbnails,
      recommend: recommend ?? this.recommend,
      sourceKey: sourceKey ?? this.sourceKey,
      comicId: comicId ?? this.comicId,
      isFavorite: isFavorite ?? this.isFavorite,
      subId: identical(subId, _copyWithSentinel) ? this.subId : subId as String?,
      isLiked: isLiked ?? this.isLiked,
      likesCount: likesCount ?? this.likesCount,
      commentCount: commentCount ?? this.commentCount,
      uploader:
          identical(uploader, _copyWithSentinel) ? this.uploader : uploader as String?,
      uploadTime:
          identical(uploadTime, _copyWithSentinel)
              ? this.uploadTime
              : uploadTime as String?,
      updateTime:
          identical(updateTime, _copyWithSentinel)
              ? this.updateTime
              : updateTime as String?,
      url: identical(url, _copyWithSentinel) ? this.url : url as String?,
      stars: identical(stars, _copyWithSentinel) ? this.stars : stars as double?,
      maxPage: maxPage ?? this.maxPage,
      comments:
          identical(comments, _copyWithSentinel)
              ? this.comments
              : comments as List<Comment>?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      "title": title,
      "subTitle": subTitle,
      "cover": cover,
      "description": description,
      "tags": tags,
      "chapters": chapters,
      "thumbnails": thumbnails,
      "recommend": null,
      "sourceKey": sourceKey,
      "comicId": comicId,
      "isFavorite": isFavorite,
      "subId": subId,
      "isLiked": isLiked,
      "likesCount": likesCount,
      "commentCount": commentCount,
      "uploader": uploader,
      "uploadTime": uploadTime,
      "updateTime": updateTime,
      "url": url,
    };
  }

  @override
  HistoryType get historyType => HistoryType(sourceTypeValueFromKey(sourceKey));

  @override
  String get id => comicId;

  ComicType get comicType => ComicType(sourceTypeValueFromKey(sourceKey));

  /// Convert tags map to plain list
  List<String> get plainTags {
    var res = <String>[];
    tags.forEach((key, value) {
      res.addAll(value.map((e) => "$key:$e"));
    });
    return res;
  }

  /// Find the first author tag
  String? findAuthor() {
    var authorNamespaces = [
      "author",
      "authors",
      "artist",
      "artists",
      "作者",
      "画师",
    ];
    for (var entry in tags.entries) {
      if (authorNamespaces.contains(entry.key.toLowerCase()) &&
          entry.value.isNotEmpty) {
        return entry.value.first;
      }
    }
    return null;
  }

  String? _validateUpdateTime(String time) {
    time = time.split(" ").first;
    var segments = time.split("-");
    if (segments.length != 3) return null;
    var year = int.tryParse(segments[0]);
    var month = int.tryParse(segments[1]);
    var day = int.tryParse(segments[2]);
    if (year == null || month == null || day == null) return null;
    if (year < 2000 || year > 3000) return null;
    if (month < 1 || month > 12) return null;
    if (day < 1 || day > 31) return null;
    return "$year-$month-$day";
  }

  String? findUpdateTime() {
    if (updateTime != null) {
      return _validateUpdateTime(updateTime!);
    }
    const acceptedNamespaces = ["更新", "最後更新", "最后更新", "update", "last update"];
    for (var entry in tags.entries) {
      if (acceptedNamespaces.contains(entry.key.toLowerCase()) &&
          entry.value.isNotEmpty) {
        var value = entry.value.first;
        return _validateUpdateTime(value);
      }
    }
    return null;
  }
}

class ArchiveInfo {
  final String title;
  final String description;
  final String id;

  ArchiveInfo.fromJson(Map<String, dynamic> json)
    : title = json.readString(_ModelJsonKey.title),
      description = json.readString(_ModelJsonKey.description),
      id = json.readString(_ModelJsonKey.id);
}

class ComicChapters {
  final Map<String, String>? _chapters;

  final Map<String, Map<String, String>>? _groupedChapters;

  /// Create a ComicChapters object with a flat map
  const ComicChapters(Map<String, String> this._chapters)
    : _groupedChapters = null;

  /// Create a ComicChapters object with a grouped map
  const ComicChapters.grouped(
    Map<String, Map<String, String>> this._groupedChapters,
  ) : _chapters = null;

  factory ComicChapters.fromJson(dynamic json) {
    if (json is! Map) throw ArgumentError("Invalid json type");
    var chapters = <String, String>{};
    var groupedChapters = <String, Map<String, String>>{};
    for (var entry in json.entries) {
      var key = entry.key;
      var value = entry.value;
      if (key is! String) throw ArgumentError("Invalid key type");
      if (value is Map) {
        groupedChapters[key] = {
          for (final entry in value.entries)
            if (entry.key is String)
              entry.key as String: entry.value.toString(),
        };
      } else {
        chapters[key] = value.toString();
      }
    }
    if (chapters.isNotEmpty) {
      return ComicChapters(chapters);
    } else if (groupedChapters.isNotEmpty) {
      return ComicChapters.grouped(groupedChapters);
    } else {
      // return a empty list.
      return ComicChapters(chapters);
    }
  }

  static fromJsonOrNull(dynamic json) {
    if (json == null) return null;
    return ComicChapters.fromJson(json);
  }

  Map<String, dynamic> toJson() {
    if (_chapters != null) {
      return _chapters;
    } else {
      return _groupedChapters!;
    }
  }

  /// Whether the chapters are grouped
  bool get isGrouped => _groupedChapters != null;

  /// All group names
  Iterable<String> get groups => _groupedChapters?.keys ?? [];

  /// All chapters.
  /// If the chapters are grouped, all groups will be merged.
  Map<String, String> get allChapters {
    if (_chapters != null) return _chapters;
    var res = <String, String>{};
    for (var entry in _groupedChapters!.values) {
      res.addAll(entry);
    }
    return res;
  }

  /// Get a group of chapters by name
  Map<String, String> getGroup(String group) {
    return _groupedChapters![group] ?? {};
  }

  /// Get a group of chapters by index(0-based)
  Map<String, String> getGroupByIndex(int index) {
    if (!isGrouped || index < 0 || index >= _groupedChapters!.length) {
      return const {};
    }
    return _groupedChapters.values.elementAt(index);
  }

  /// Get total number of chapters
  int get length {
    if (!isGrouped) return _chapters!.length;
    return _groupedChapters!.values.fold<int>(0, (sum, e) => sum + e.length);
  }

  /// Get the number of groups
  int get groupCount => _groupedChapters?.length ?? 0;

  /// Iterate all chapter ids
  Iterable<String> get ids sync* {
    if (isGrouped) {
      for (var entry in _groupedChapters!.values) {
        yield* entry.keys;
      }
    } else {
      yield* _chapters!.keys;
    }
  }

  /// Iterate all chapter titles
  Iterable<String> get titles sync* {
    if (isGrouped) {
      for (var entry in _groupedChapters!.values) {
        yield* entry.values;
      }
    } else {
      yield* _chapters!.values;
    }
  }

  String? operator [](String key) {
    if (isGrouped) {
      for (var entry in _groupedChapters!.values) {
        if (entry.containsKey(key)) return entry[key];
      }
      return null;
    } else {
      return _chapters![key];
    }
  }
}

class PageJumpTarget {
  final String sourceKey;

  final String page;

  final Map<String, dynamic>? attributes;

  const PageJumpTarget(this.sourceKey, this.page, this.attributes);

  static PageJumpTarget parse(String sourceKey, dynamic value) {
    if (value is Map) {
      final map = Map<String, dynamic>.from(value);
      if (map[_ModelJsonKey.page] != null) {
        return PageJumpTarget(
          sourceKey,
          map[_ModelJsonKey.page] ?? "search",
          map[_ModelJsonKey.attributes],
        );
      } else if (map[_ModelJsonKey.action] != null) {
        // old version `onClickTag`
        var page = map[_ModelJsonKey.action];
        if (page == "search") {
          return PageJumpTarget(sourceKey, "search", {
            _ModelJsonKey.text: map[_ModelJsonKey.keyword],
          });
        } else if (page == "category") {
          return PageJumpTarget(sourceKey, "category", {
            _ModelJsonKey.category: map[_ModelJsonKey.keyword],
            _ModelJsonKey.param: map[_ModelJsonKey.param],
          });
        } else {
          return PageJumpTarget(sourceKey, page, null);
        }
      }
    } else if (value is String) {
      // old version string encoding. search: `search:keyword`, category: `category:keyword` or `category:keyword@param`
      final sep = value.indexOf(':');
      if (sep <= 0) {
        return PageJumpTarget(sourceKey, "Invalid Data", null);
      }
      var page = value.substring(0, sep);
      var payload = value.substring(sep + 1);
      if (page == "search") {
        return PageJumpTarget(sourceKey, "search", {"text": payload});
      } else if (page == "category") {
        var c = payload;
        if (c.contains('@')) {
          var parts = c.split('@');
          return PageJumpTarget(sourceKey, "category", {
            "category": parts[0],
            "param": parts[1],
          });
        } else {
          return PageJumpTarget(sourceKey, "category", {"category": c});
        }
      } else {
        return PageJumpTarget(sourceKey, page, null);
      }
    }
    return PageJumpTarget(sourceKey, "Invalid Data", null);
  }

  void jump(BuildContext context) {
    if (page == "search") {
      context.to(
        () => SearchResultPage(
          text:
              attributes?[_ModelJsonKey.text] ??
              attributes?[_ModelJsonKey.keyword] ??
              "",
          sourceKey: sourceKey,
          options: List.from(attributes?[_ModelJsonKey.options] ?? []),
        ),
      );
    } else if (page == "category") {
      final source = ComicSource.find(sourceKey);
      final categoryData = source?.categoryData;
      if (categoryData == null) {
        AppDiagnostics.error('source.page_jump', 'Category source unavailable', message: 'category_source_unavailable', data: {'sourceKey': sourceKey});
        context.showMessage(message: "Comic source is unavailable".tl);
        return;
      }
      final category = attributes?[_ModelJsonKey.category]?.toString();
      if (category == null || category.isEmpty) {
        AppDiagnostics.error('source.page_jump', 'Category name required', message: 'category_name_required', data: {'sourceKey': sourceKey});
        context.showMessage(message: "Category is unavailable".tl);
        return;
      }
      context.to(
        () => CategoryComicsPage(
          categoryKey: categoryData.key,
          category: category,
          options: List.from(attributes?[_ModelJsonKey.options] ?? []),
          param: attributes?[_ModelJsonKey.param],
        ),
      );
    } else {
      AppDiagnostics.error('source.page_jump', 'Unknown page', message: 'unknown_page', data: {'page': page.toString()});
    }
  }
}
