import 'package:venera/features/sources/comic_source/comic_source.dart';
import 'package:venera/foundation/sources/source_ref.dart';

class ReaderActivityItem implements Comic {
  const ReaderActivityItem({
    required this.comicId,
    required this.title,
    required this.subtitle,
    required this.cover,
    required this.sourceKey,
    required this.sourceRef,
    required this.chapterId,
    required this.pageIndex,
    required this.lastReadAt,
  });

  final String comicId;

  @override
  final String title;

  @override
  final String subtitle;

  @override
  final String cover;

  @override
  final String sourceKey;

  final SourceRef sourceRef;
  final String chapterId;
  final int pageIndex;
  final DateTime lastReadAt;

  @override
  String get id => comicId;

  @override
  String get description {
    final parts = <String>[];
    if (chapterId.isNotEmpty && chapterId != '0') {
      parts.add('Chapter $chapterId');
    }
    if (pageIndex > 0) {
      parts.add('Page $pageIndex');
    }
    return parts.join(' - ');
  }

  @override
  String? get favoriteId => null;

  @override
  String? get language => null;

  @override
  int? get maxPage => null;

  @override
  double? get stars => null;

  @override
  List<String>? get tags => null;

  @override
  Map<String, dynamic> toJson() {
    return {
      'comicId': comicId,
      'title': title,
      'subtitle': subtitle,
      'cover': cover,
      'sourceKey': sourceKey,
      'sourceRef': sourceRef.toJson(),
      'chapterId': chapterId,
      'pageIndex': pageIndex,
      'lastReadAt': lastReadAt.toIso8601String(),
    };
  }
}
