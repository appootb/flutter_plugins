import 'dart:async';
import 'dart:math';

import 'package:uuid/uuid.dart';

import '../redaction/redactor.dart';
import '../sinks/log_sink.dart';
import '../telemetry/telemetry.dart';
import 'log_event.dart';
import 'log_level.dart';
import 'logger_config.dart';

class Logger {
  Logger({
    required this.engineId,
    LoggerConfig? config,
    Redactor? redactor,
    List<LogSink>? sinks,
    ErrorReporter? errorReporter,
    Uuid? uuid,
    DateTime Function()? now,
  }) : config = config ?? LoggerConfig(),
       redactor = redactor ?? Redactor(),
       _sinks = List<LogSink>.unmodifiable(sinks ?? const <LogSink>[]),
       _errorReporter = errorReporter ?? const NoopErrorReporter(),
       _uuid = uuid ?? const Uuid(),
       _now = now ?? DateTime.now,
       sessionId = (uuid ?? const Uuid()).v4(),
       threadId = _randomThreadLabel();

  final String engineId;
  final LoggerConfig config;
  final Redactor redactor;
  final String sessionId;
  final String threadId;

  final List<LogSink> _sinks;
  final ErrorReporter _errorReporter;
  final Uuid _uuid;
  final DateTime Function() _now;
  final Random _rand = Random();
  final Map<String, _RateState> _rate = <String, _RateState>{};

  static String _randomThreadLabel() {
    final r = Random();
    final n = r.nextInt(1 << 32).toRadixString(16).padLeft(8, '0');
    return 'iso_$n';
  }

  String newRequestId({String prefix = 'req_'}) => '$prefix${_uuid.v7()}';

  bool _shouldLog(String module, LogLevel level) {
    final min = config.effectiveLevelForModule(module);
    return level.weight >= min.weight;
  }

  bool _passesSampling(String module) {
    var r = config.effectiveSampleRateForModule(module);
    if (r >= 1.0) return true;
    if (r <= 0.0) return false;
    return _rand.nextDouble() < r;
  }

  bool _passesRateLimit(String key) {
    final window = config.rateLimitWindow;
    final maxPerKey = config.rateLimitMaxPerKey;
    if (window == null || maxPerKey <= 0) return true;

    final nowMs = _now().millisecondsSinceEpoch;
    final winMs = window.inMilliseconds <= 0 ? 1 : window.inMilliseconds;
    final slot = nowMs ~/ winMs;

    final st = _rate[key];
    if (st == null || st.slot != slot) {
      _rate[key] = _RateState(slot: slot, count: 1);
      return true;
    }

    if (st.count >= maxPerKey) return false;
    st.count += 1;
    return true;
  }

  Map<String, Object?>? _sanitizeContext(Map<String, Object?>? ctx) {
    if (ctx == null || ctx.isEmpty) return null;
    Object? sanitizeValue(Object? v) {
      if (v == null) return null;
      if (v is String) {
        return redactor.truncate(v, maxLen: config.maxStringLength);
      }
      if (v is num || v is bool) return v;
      if (v is DateTime) return v.toIso8601String();
      if (v is Uri) return redactor.redactUrl(v).toString();
      if (v is Map) {
        final out = <String, Object?>{};
        for (final e in v.entries) {
          out['${e.key}'] = sanitizeValue(e.value);
        }
        return out;
      }
      if (v is Iterable) return v.map(sanitizeValue).toList(growable: false);
      return redactor.truncate(v.toString(), maxLen: config.maxStringLength);
    }

    return <String, Object?>{
      for (final e in ctx.entries) e.key: sanitizeValue(e.value),
    };
  }

  Future<void> log(
    LogLevel level,
    String module,
    String message, {
    Map<String, Object?>? ctx,
    Object? error,
    StackTrace? stackTrace,
    String? requestId,
  }) async {
    if (!_shouldLog(module, level)) return;
    if (!_passesSampling(module)) return;
    final key = '${level.jsonName}|$module|$message';
    if (!_passesRateLimit(key)) return;

    final ev = LogEvent(
      ts: _now(),
      level: level,
      module: module,
      message: redactor.truncate(message, maxLen: config.maxStringLength),
      context: _sanitizeContext(ctx),
      error: error == null
          ? null
          : redactor.truncate(error.toString(), maxLen: config.maxStringLength),
      stack: stackTrace == null
          ? null
          : redactor.truncate(stackTrace.toString(), maxLen: 8192),
      engineId: engineId,
      sessionId: sessionId,
      requestId: requestId,
      processId: null,
      threadId: threadId,
    );

    if (level.weight >= LogLevel.error.weight) {
      await _errorReporter.report(
        error: error ?? message,
        stackTrace: stackTrace,
        context: ev.toJsonV1(),
      );
    }

    await Future.wait(_sinks.map((s) => s.log(ev)));
  }

  /// Fire-and-forget variant: does not await sinks/reporters.
  void emit(
    LogLevel level,
    String module,
    String message, {
    Map<String, Object?>? ctx,
    Object? error,
    StackTrace? stackTrace,
    String? requestId,
  }) {
    if (!_shouldLog(module, level)) return;
    if (!_passesSampling(module)) return;
    final key = '${level.jsonName}|$module|$message';
    if (!_passesRateLimit(key)) return;

    final ev = LogEvent(
      ts: _now(),
      level: level,
      module: module,
      message: redactor.truncate(message, maxLen: config.maxStringLength),
      context: _sanitizeContext(ctx),
      error: error == null
          ? null
          : redactor.truncate(error.toString(), maxLen: config.maxStringLength),
      stack: stackTrace == null
          ? null
          : redactor.truncate(stackTrace.toString(), maxLen: 8192),
      engineId: engineId,
      sessionId: sessionId,
      requestId: requestId,
      processId: null,
      threadId: threadId,
    );

    if (level.weight >= LogLevel.error.weight) {
      unawaited(
        _errorReporter.report(
          error: error ?? message,
          stackTrace: stackTrace,
          context: ev.toJsonV1(),
        ),
      );
    }

    for (final s in _sinks) {
      try {
        unawaited(s.log(ev));
      } catch (_) {
        // Best-effort.
      }
    }
  }

  Future<void> trace(
    String module,
    String message, {
    Map<String, Object?>? ctx,
    String? requestId,
  }) => log(LogLevel.trace, module, message, ctx: ctx, requestId: requestId);

  void emitTrace(
    String module,
    String message, {
    Map<String, Object?>? ctx,
    String? requestId,
  }) => emit(LogLevel.trace, module, message, ctx: ctx, requestId: requestId);

  Future<void> debug(
    String module,
    String message, {
    Map<String, Object?>? ctx,
    String? requestId,
  }) => log(LogLevel.debug, module, message, ctx: ctx, requestId: requestId);

  void emitDebug(
    String module,
    String message, {
    Map<String, Object?>? ctx,
    String? requestId,
  }) => emit(LogLevel.debug, module, message, ctx: ctx, requestId: requestId);

  Future<void> info(
    String module,
    String message, {
    Map<String, Object?>? ctx,
    String? requestId,
  }) => log(LogLevel.info, module, message, ctx: ctx, requestId: requestId);

  void emitInfo(
    String module,
    String message, {
    Map<String, Object?>? ctx,
    String? requestId,
  }) => emit(LogLevel.info, module, message, ctx: ctx, requestId: requestId);

  Future<void> warn(
    String module,
    String message, {
    Map<String, Object?>? ctx,
    String? requestId,
  }) => log(LogLevel.warn, module, message, ctx: ctx, requestId: requestId);

  void emitWarn(
    String module,
    String message, {
    Map<String, Object?>? ctx,
    String? requestId,
  }) => emit(LogLevel.warn, module, message, ctx: ctx, requestId: requestId);

  Future<void> error(
    String module,
    String message, {
    Map<String, Object?>? ctx,
    Object? error,
    StackTrace? stackTrace,
    String? requestId,
  }) => log(
    LogLevel.error,
    module,
    message,
    ctx: ctx,
    error: error,
    stackTrace: stackTrace,
    requestId: requestId,
  );

  void emitError(
    String module,
    String message, {
    Map<String, Object?>? ctx,
    Object? error,
    StackTrace? stackTrace,
    String? requestId,
  }) => emit(
    LogLevel.error,
    module,
    message,
    ctx: ctx,
    error: error,
    stackTrace: stackTrace,
    requestId: requestId,
  );

  Future<void> fatal(
    String module,
    String message, {
    Map<String, Object?>? ctx,
    Object? error,
    StackTrace? stackTrace,
    String? requestId,
  }) => log(
    LogLevel.fatal,
    module,
    message,
    ctx: ctx,
    error: error,
    stackTrace: stackTrace,
    requestId: requestId,
  );

  void emitFatal(
    String module,
    String message, {
    Map<String, Object?>? ctx,
    Object? error,
    StackTrace? stackTrace,
    String? requestId,
  }) => emit(
    LogLevel.fatal,
    module,
    message,
    ctx: ctx,
    error: error,
    stackTrace: stackTrace,
    requestId: requestId,
  );

  Future<void> flush() async => Future.wait(_sinks.map((s) => s.flush()));

  Future<void> close() async => Future.wait(_sinks.map((s) => s.close()));
}

class _RateState {
  _RateState({required this.slot, required this.count});

  final int slot;
  int count;
}
