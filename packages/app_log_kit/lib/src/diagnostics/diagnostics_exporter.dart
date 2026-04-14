import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

class DiagnosticsExporter {
  DiagnosticsExporter({required this.logsDirectory});

  final Directory logsDirectory;

  /// Exports a diagnostics zip containing:
  /// - logs (all files under [logsDirectory])
  /// - optional metadata provided by the host app
  Future<File> exportZip({
    required Directory outputDirectory,
    String? fileName,
    Map<String, Object?>? metadataJson,
  }) async {
    await outputDirectory.create(recursive: true);
    final name =
        fileName ??
        'diagnostics-${DateTime.now().toIso8601String().replaceAll(':', '-')}.zip';
    final outPath = p.join(outputDirectory.path, name);

    final encoder = ZipFileEncoder();
    encoder.create(outPath);

    if (await logsDirectory.exists()) {
      await encoder.addDirectory(logsDirectory, includeDirName: true);
    }

    if (metadataJson != null && metadataJson.isNotEmpty) {
      final tmp = File(
        p.join(outputDirectory.path, '.app_log_kit_metadata.json'),
      );
      await tmp.writeAsString(_prettyJson(metadataJson));
      encoder.addFile(tmp, 'metadata.json');
      try {
        await tmp.delete();
      } catch (_) {}
    }

    encoder.close();
    return File(outPath);
  }

  String _prettyJson(Map<String, Object?> map) {
    // Avoid pulling extra deps; archive already depends on convert internals.
    // This is a minimal pretty-ish output.
    final b = StringBuffer();
    b.writeln('{');
    var first = true;
    for (final e in map.entries) {
      if (!first) b.writeln(',');
      first = false;
      b.write('  "${e.key}": "${e.value}"');
    }
    b.writeln();
    b.writeln('}');
    return b.toString();
  }
}
