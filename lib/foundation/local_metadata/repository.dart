import 'dart:convert';

import 'package:venera/foundation/log.dart';
import 'package:venera/foundation/local_metadata/models.dart';
import 'package:venera/utils/io.dart';

class LocalMetadataRepository {
  LocalMetadataRepository(this._filePath);

  final String _filePath;

  LocalMetadataDocument _doc = LocalMetadataDocument.empty();

  LocalMetadataDocument get document => _doc;

  Future<void> init() async {
    final file = File(_filePath);
    if (!await file.exists()) {
      _doc = LocalMetadataDocument.empty();
      return;
    }
    try {
      final content = await file.readAsString();
      final decoded = jsonDecode(content);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Invalid metadata root');
      }
      _doc = LocalMetadataDocument.fromJson(decoded);
    } catch (e) {
      Log.warning(
        'LocalMetadata',
        'Invalid metadata sidecar; using empty fallback document: $e',
      );
      _doc = LocalMetadataDocument.empty();
    }
  }

  LocalSeriesMeta? getSeries(String seriesKey) => _doc.series[seriesKey];

  Future<void> upsertSeries(LocalSeriesMeta series) async {
    final newSeries = Map<String, LocalSeriesMeta>.from(_doc.series);
    newSeries[series.seriesKey] = series;
    final newDoc = LocalMetadataDocument(
      version: LocalMetadataDocument.currentVersion,
      series: newSeries,
    );
    await _persist(newDoc);
    _doc = newDoc;
  }

  Future<void> removeSeries(String seriesKey) async {
    if (!_doc.series.containsKey(seriesKey)) {
      return;
    }
    final newSeries = Map<String, LocalSeriesMeta>.from(_doc.series);
    newSeries.remove(seriesKey);
    final newDoc = LocalMetadataDocument(
      version: LocalMetadataDocument.currentVersion,
      series: newSeries,
    );
    await _persist(newDoc);
    _doc = newDoc;
  }

  Future<void> _persist(LocalMetadataDocument document) async {
    final file = File(_filePath);
    await file.parent.create(recursive: true);

    final tmpPath = '$_filePath.tmp';
    final tmpFile = File(tmpPath);
    final payload = jsonEncode(document.toJson());

    await tmpFile.writeAsString(payload, flush: true);
    try {
      await tmpFile.rename(_filePath);
    } on FileSystemException {
      if (await file.exists()) {
        await file.delete();
      }
      await tmpFile.rename(_filePath);
    }
  }
}
