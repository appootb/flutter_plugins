import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../logger/log_event.dart';
import 'log_sink.dart';

class FileSink implements LogSink {
  FileSink({
    required this.directory,
    required this.engineId,
    this.maxBytesPerFile = 8 * 1024 * 1024,
    this.keepDays = 7,
    this.maxTotalBytes = 100 * 1024 * 1024,
    this.compressRotated = true,
  }) {
    // Start the background writer immediately.
    _worker = _run();
  }

  final Directory directory;
  final String engineId;
  final int maxBytesPerFile;
  final int keepDays;
  final int maxTotalBytes;
  final bool compressRotated;

  final StreamController<LogEvent> _q = StreamController<LogEvent>(sync: false);
  late final Future<void> _worker;

  IOSink? _sink;
  File? _currentFile;
  String? _currentDayKey;
  int _currentIndex = 0;
  int _currentBytes = 0;

  static String _dayKey(DateTime ts) =>
      '${ts.year.toString().padLeft(4, '0')}${ts.month.toString().padLeft(2, '0')}${ts.day.toString().padLeft(2, '0')}';

  String _baseNameFor(DateTime ts, {required int index}) {
    final day = _dayKey(ts);
    // Keep the "daily" prefix, but allow multiple files per day for size rotation.
    // Example: mobile-20260414-000.jsonl, mobile-20260414-001.jsonl
    final suffix = index.toString().padLeft(3, '0');
    return '$engineId-$day-$suffix.jsonl';
  }

  Future<void> _ensureOpenFor(LogEvent event) async {
    await directory.create(recursive: true);
    final dayKey = _dayKey(event.ts);
    final needNewDay = _currentDayKey != dayKey;
    final needRotateBySize = _currentBytes >= maxBytesPerFile;
    if (_sink == null ||
        _currentFile == null ||
        needNewDay ||
        needRotateBySize) {
      await _rotateAndOpen(
        event.ts,
        keepOldOpen: false,
        rotateBecauseSize: needRotateBySize && !needNewDay,
      );
    }
  }

  Future<void> _rotateAndOpen(
    DateTime ts, {
    required bool keepOldOpen,
    required bool rotateBecauseSize,
  }) async {
    final oldFile = _currentFile;
    final oldSink = _sink;

    final newDayKey = _dayKey(ts);
    if (_currentDayKey != newDayKey) {
      _currentDayKey = newDayKey;
      _currentIndex = 0;
    } else if (rotateBecauseSize) {
      _currentIndex += 1;
    }

    final filePath = p.join(
      directory.path,
      _baseNameFor(ts, index: _currentIndex),
    );
    _currentFile = File(filePath);
    if (await _currentFile!.exists()) {
      _currentBytes = await _currentFile!.length();
    } else {
      _currentBytes = 0;
    }
    _sink = _currentFile!.openWrite(mode: FileMode.append, encoding: utf8);

    if (!keepOldOpen && oldSink != null) {
      await oldSink.flush();
      await oldSink.close();
    }
    if (oldFile != null &&
        compressRotated &&
        _currentFile != null &&
        oldFile.path != _currentFile!.path) {
      // Best-effort compress previous file if it isn't already compressed.
      unawaited(_gzipIfWorthwhile(oldFile));
    }
    unawaited(_enforceRetention());
  }

  Future<void> _gzipIfWorthwhile(File file) async {
    try {
      if (!await file.exists()) return;
      if (file.path.endsWith('.gz')) return;
      final len = await file.length();
      if (len <= 0) return;
      final gzPath = '${file.path}.gz';
      final gzFile = File(gzPath);
      if (await gzFile.exists()) return;
      final bytes = await file.readAsBytes();
      final gzBytes = GZipCodec().encode(bytes);
      await gzFile.writeAsBytes(gzBytes, flush: true);
      // Keep original? PRD suggests compress old files; we'll delete original after successful gzip.
      await file.delete();
    } catch (_) {
      // Best-effort.
    }
  }

  Future<void> _enforceRetention() async {
    try {
      if (!await directory.exists()) return;
      final now = DateTime.now();
      final cutoff = now.subtract(Duration(days: keepDays));
      final entities = await directory.list().toList();
      final files = entities.whereType<File>().toList();

      // Delete by age first (best-effort by mtime).
      for (final f in files) {
        final stat = await f.stat();
        if (keepDays > 0 && stat.modified.isBefore(cutoff)) {
          try {
            await f.delete();
          } catch (_) {}
        }
      }

      // Enforce total size cap: delete oldest first.
      final entities2 = await directory.list().toList();
      final remaining = entities2.whereType<File>().toList();
      final stats = <File, FileStat>{};
      for (final f in remaining) {
        stats[f] = await f.stat();
      }
      int total = stats.values.fold<int>(0, (a, s) => a + s.size);
      if (maxTotalBytes <= 0) return;
      if (total <= maxTotalBytes) return;

      final sorted = remaining.toList()
        ..sort((a, b) => stats[a]!.modified.compareTo(stats[b]!.modified));
      for (final f in sorted) {
        if (total <= maxTotalBytes) break;
        try {
          final size = stats[f]!.size;
          await f.delete();
          total -= size;
        } catch (_) {}
      }
    } catch (_) {
      // Best-effort.
    }
  }

  Future<void> _run() async {
    await for (final event in _q.stream) {
      try {
        await _ensureOpenFor(event);
        final line = '${event.toJsonlLine()}\n';
        _sink!.write(line);
        _currentBytes += utf8.encode(line).length;
      } catch (_) {
        // Best-effort: swallow errors.
      }
    }
  }

  @override
  Future<void> log(LogEvent event) async {
    if (_q.isClosed) return;
    _q.add(event);
  }

  @override
  Future<void> flush() async {
    try {
      await _sink?.flush();
    } catch (_) {}
  }

  @override
  Future<void> close() async {
    try {
      await _q.close();
    } catch (_) {}
    await _worker;
    try {
      await _sink?.flush();
      await _sink?.close();
    } catch (_) {}
    _sink = null;
  }
}
