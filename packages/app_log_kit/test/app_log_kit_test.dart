import 'package:app_log_kit/app_log_kit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('LogEvent jsonl includes required fields', () {
    final ev = LogEvent(
      ts: DateTime.parse('2026-04-14T10:22:33.456+02:00'),
      level: LogLevel.info,
      module: 'http',
      message: 'request complete',
      engineId: 'dashboard',
      sessionId: 'sid',
      requestId: 'rid',
      context: <String, Object?>{
        'http': <String, Object?>{'status': 200},
      },
    );
    final line = ev.toJsonlLine();
    expect(line.contains('"v":1'), isTrue);
    expect(line.contains('"lvl":"info"'), isTrue);
    expect(line.contains('"eid":"dashboard"'), isTrue);
  });

  test('MemorySink keeps last N events', () async {
    final sink = MemorySink(capacity: 2);
    await sink.log(
      LogEvent(
        ts: DateTime.now(),
        level: LogLevel.info,
        module: 'm',
        message: '1',
        engineId: 'e',
      ),
    );
    await sink.log(
      LogEvent(
        ts: DateTime.now(),
        level: LogLevel.info,
        module: 'm',
        message: '2',
        engineId: 'e',
      ),
    );
    await sink.log(
      LogEvent(
        ts: DateTime.now(),
        level: LogLevel.info,
        module: 'm',
        message: '3',
        engineId: 'e',
      ),
    );
    expect(sink.snapshot().length, 2);
    expect(sink.snapshot().first.message, '2');
  });

  test('LoggerConfig sampling and rate limit can suppress logs', () async {
    final memory = MemorySink(capacity: 999);
    final logger = Logger(
      engineId: 'e',
      sinks: <LogSink>[memory],
      config: LoggerConfig(
        level: LogLevel.trace,
        enableDebugLogging: true,
        sampleRate: 0.0,
        // suppress everything
        rateLimitWindow: const Duration(seconds: 1),
        rateLimitMaxPerKey: 1,
      ),
    );

    logger.emitInfo('m', 'hello');
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(memory.snapshot(), isEmpty);

    // Now allow all, but rate limit to 1 per window.
    logger.config.sampleRate = 1.0;
    logger.emitInfo('m', 'same');
    logger.emitInfo('m', 'same');
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(memory.snapshot().length, 1);
  });
}
