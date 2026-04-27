import 'dart:io';

final RegExp _tokenRegex = RegExp(r'(\d+|\D+)');
final RegExp _nameSegmentRegex = RegExp(r'[\\/]');

String _fileNameFromPath(String path) {
  final parts = path.split(_nameSegmentRegex);
  return parts.isEmpty ? path : parts.last;
}

bool isHiddenOrMacMetadataPath(String path) {
  if (path.isEmpty) return true;
  final normalized = path.replaceAll('\\', '/');
  final parts = normalized.split('/');
  final baseName = parts.isEmpty ? normalized : parts.last;
  for (final part in parts) {
    if (part.isEmpty) continue;
    if (part == '__MACOSX') return true;
    if (part.startsWith('._')) return true;
  }
  if (baseName.startsWith('.')) return true;
  return false;
}

int naturalCompare(String a, String b) {
  final aTokens = _tokenRegex.allMatches(a).map((m) => m.group(0)!).toList();
  final bTokens = _tokenRegex.allMatches(b).map((m) => m.group(0)!).toList();
  final length = aTokens.length < bTokens.length ? aTokens.length : bTokens.length;

  for (var i = 0; i < length; i++) {
    final x = aTokens[i];
    final y = bTokens[i];
    final xNum = int.tryParse(x);
    final yNum = int.tryParse(y);

    if (xNum != null && yNum != null) {
      final cmp = xNum.compareTo(yNum);
      if (cmp != 0) return cmp;
      continue;
    }

    final cmp = x.toLowerCase().compareTo(y.toLowerCase());
    if (cmp != 0) return cmp;
  }

  return aTokens.length.compareTo(bTokens.length);
}

void naturalSortStrings(List<String> values) {
  values.sort(naturalCompare);
}

void naturalSortFiles(List<File> files) {
  files.sort((a, b) =>
      naturalCompare(_fileNameFromPath(a.path), _fileNameFromPath(b.path)));
}

bool isArchiveExtension(String ext) {
  final normalized = ext.toLowerCase();
  return normalized == 'cbz' ||
      normalized == 'zip' ||
      normalized == '7z' ||
      normalized == 'cb7';
}

bool isSupportedImportExtension(String ext) {
  final normalized = ext.toLowerCase();
  return normalized == 'pdf' || isArchiveExtension(normalized);
}
