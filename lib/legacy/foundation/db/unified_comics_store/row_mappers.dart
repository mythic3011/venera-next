part of '../unified_comics_store.dart';

extension _UnifiedComicsStoreRowMappers on UnifiedComicsStore {
  List<String> _splitGroupedStrings(String? raw) {
    if (raw == null || raw.isEmpty) {
      return const <String>[];
    }
    return raw
        .split(',')
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
  }
}
