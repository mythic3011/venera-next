import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:venera/foundation/diagnostics/log_storage_writer.dart';
import 'package:venera/utils/io.dart';

void main() {
  test('appendJson preserves append ordering as NDJSON lines', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'venera_log_storage_writer_order_',
    );
    final path = FilePath.join(tempDir.path, 'logs', 'diagnostics.ndjson');
    final writer = LogStorageWriter(pathResolver: () => path);

    await writer.appendJson({
      'timestamp': '2026-05-04T00:00:00Z',
      'level': 'info',
      'channel': 'test.channel',
      'message': 'first',
      'data': {'seq': 1},
    });
    await writer.appendJson({
      'timestamp': '2026-05-04T00:00:01Z',
      'level': 'warn',
      'channel': 'test.channel',
      'message': 'second',
      'data': {'seq': 2},
    });
    await writer.appendJson({
      'timestamp': '2026-05-04T00:00:02Z',
      'level': 'error',
      'channel': 'test.channel',
      'message': 'third',
      'data': {'seq': 3},
    });
    await writer.closeForTesting();

    final file = File(path);
    expect(await file.exists(), isTrue);
    final lines = await file.readAsLines();
    expect(lines.length, 3);

    final decoded = lines
        .map((line) => jsonDecode(line) as Map<String, dynamic>)
        .toList(growable: false);
    expect(decoded[0]['message'], 'first');
    expect(decoded[1]['message'], 'second');
    expect(decoded[2]['message'], 'third');
    expect(decoded[0]['data']['seq'], 1);
    expect(decoded[1]['data']['seq'], 2);
    expect(decoded[2]['data']['seq'], 3);

    await tempDir.delete(recursive: true);
  });

  test('appendLine writes one JSON object per line', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'venera_log_storage_writer_lines_',
    );
    final path = FilePath.join(tempDir.path, 'logs', 'diagnostics.ndjson');
    final writer = LogStorageWriter(pathResolver: () => path);

    await writer.appendLine('{"level":"info","message":"a"}');
    await writer.appendLine('{"level":"error","message":"b"}');
    await writer.closeForTesting();

    final content = await File(path).readAsString();
    final lines = content.trimRight().split('\n');
    expect(lines.length, 2);
    expect(lines[0], '{"level":"info","message":"a"}');
    expect(lines[1], '{"level":"error","message":"b"}');

    await tempDir.delete(recursive: true);
  });

  test('rotates current file when size exceeds maxCurrentBytes', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'venera_log_storage_writer_rotate_',
    );
    final path = FilePath.join(tempDir.path, 'logs', 'diagnostics.ndjson');
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsString('x' * 64);

    final writer = LogStorageWriter(
      pathResolver: () => path,
      retentionPolicy: const LogRetentionPolicy(
        maxCurrentBytes: 10,
        maxArchives: 5,
      ),
    );
    await writer.appendLine('{"level":"info","message":"after-rotate"}');
    await writer.closeForTesting();

    final current = await file.readAsString();
    expect(current.contains('after-rotate'), isTrue);

    final entries = await file.parent.list().toList();
    final archives = entries
        .whereType<File>()
        .where((entry) => entry.path.startsWith('$path.'))
        .toList(growable: false);
    expect(archives.length, 1);
    final archived = await archives.first.readAsString();
    expect(archived, 'x' * 64);

    await tempDir.delete(recursive: true);
  });

  test('keeps only maxArchives newest rotated files', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'venera_log_storage_writer_archive_trim_',
    );
    final path = FilePath.join(tempDir.path, 'logs', 'diagnostics.ndjson');
    final writer = LogStorageWriter(
      pathResolver: () => path,
      retentionPolicy: const LogRetentionPolicy(
        maxCurrentBytes: 1,
        maxArchives: 2,
      ),
    );

    for (var i = 0; i < 5; i++) {
      await writer.appendLine('{"message":"$i"}');
      await File(path).writeAsString('xxxx', mode: FileMode.append);
    }
    await writer.closeForTesting();

    final entries = await Directory(File(path).parent.path).list().toList();
    final archives = entries
        .whereType<File>()
        .where((entry) => entry.path.startsWith('$path.'))
        .toList(growable: false);
    expect(archives.length, 2);

    await tempDir.delete(recursive: true);
  });

  test('compresses rotated archives when policy enables compression', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'venera_log_storage_writer_compress_',
    );
    final path = FilePath.join(tempDir.path, 'logs', 'diagnostics.ndjson');
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsString('compress-me');

    final writer = LogStorageWriter(
      pathResolver: () => path,
      retentionPolicy: const LogRetentionPolicy(
        maxCurrentBytes: 1,
        maxArchives: 3,
        compressArchives: true,
      ),
    );
    await writer.appendLine('{"message":"after"}');
    await writer.closeForTesting();

    final entries = await file.parent.list().toList();
    final gzipArchives = entries
        .whereType<File>()
        .where((entry) => entry.path.startsWith('$path.'))
        .where((entry) => entry.path.endsWith('.gz'))
        .toList(growable: false);
    expect(gzipArchives.length, 1);
    final decoded = utf8.decode(
      gzip.decode(await gzipArchives.first.readAsBytes()),
    );
    expect(decoded, 'compress-me');

    await tempDir.delete(recursive: true);
  });

  test('creates lock file during rotation flow', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'venera_log_storage_writer_lock_',
    );
    final path = FilePath.join(tempDir.path, 'logs', 'diagnostics.ndjson');
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsString('trigger-rotate');

    final writer = LogStorageWriter(
      pathResolver: () => path,
      retentionPolicy: const LogRetentionPolicy(
        maxCurrentBytes: 1,
        maxArchives: 2,
      ),
    );
    await writer.appendLine('{"message":"after"}');
    await writer.closeForTesting();

    final lockFile = File(FilePath.join(file.parent.path, 'log.lock'));
    expect(await lockFile.exists(), isTrue);

    await tempDir.delete(recursive: true);
  });
}
