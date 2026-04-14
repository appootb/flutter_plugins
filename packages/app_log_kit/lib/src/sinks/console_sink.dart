import 'dart:convert';
import 'dart:io';

import '../logger/log_event.dart';
import 'log_sink.dart';

class ConsoleSink implements LogSink {
  ConsoleSink({
    this.useStderrForError = true,
    this.includeContext = true,
    this.includeError = true,
    this.maxFieldLength = 2048,
  });

  final bool useStderrForError;
  final bool includeContext;
  final bool includeError;
  final int maxFieldLength;

  String _truncate(String s) {
    if (maxFieldLength <= 0) return '';
    if (s.length <= maxFieldLength) return s;
    return '${s.substring(0, maxFieldLength)}…';
  }

  @override
  Future<void> log(LogEvent event) async {
    var line =
        '[${event.ts.toIso8601String()}] ${event.level.jsonName.toUpperCase()} '
        '${event.module}: ${event.message}';

    if (includeContext && event.context != null && event.context!.isNotEmpty) {
      line = '$line ctx=${_truncate(jsonEncode(event.context))}';
    }

    if (includeError) {
      if (event.error != null && event.error!.isNotEmpty) {
        line = '$line err=${_truncate(event.error!)}';
      }
      if (event.stack != null && event.stack!.isNotEmpty) {
        line = '$line stk=${_truncate(event.stack!)}';
      }
    }

    if (useStderrForError && (event.level.weight >= 50)) {
      stderr.writeln(line);
    } else {
      // ignore: avoid_print
      print(line);
    }
  }

  @override
  Future<void> flush() async {}

  @override
  Future<void> close() async {}
}
