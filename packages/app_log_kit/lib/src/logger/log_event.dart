import 'dart:convert';

import 'log_level.dart';

/// JSONL schema version for file logs.
const int kLogSchemaVersionV1 = 1;

class LogEvent {
  LogEvent({
    required this.ts,
    required this.level,
    required this.module,
    required this.message,
    this.context,
    this.error,
    this.stack,
    required this.engineId,
    this.sessionId,
    this.requestId,
    this.processId,
    this.threadId,
  });

  final DateTime ts;
  final LogLevel level;
  final String module;
  final String message;
  final Map<String, Object?>? context;
  final String? error;
  final String? stack;
  final String engineId;
  final String? sessionId;
  final String? requestId;
  final int? processId;
  final String? threadId;

  Map<String, Object?> toJsonV1() {
    return <String, Object?>{
      'v': kLogSchemaVersionV1,
      'ts': ts.toIso8601String(),
      'lvl': level.jsonName,
      'mod': module,
      'msg': message,
      'ctx': context == null || context!.isEmpty ? null : context,
      'err': error,
      'stk': stack,
      'eid': engineId,
      'sid': sessionId,
      'rid': requestId,
      'pid': processId,
      'tid': threadId,
    }..removeWhere((_, v) => v == null);
  }

  /// JSONL line (no trailing newline).
  String toJsonlLine() => jsonEncode(toJsonV1());
}
