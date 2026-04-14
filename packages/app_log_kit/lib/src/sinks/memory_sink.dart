import '../logger/log_event.dart';
import 'log_sink.dart';

class MemorySink implements LogSink {
  MemorySink({this.capacity = 500});

  final int capacity;
  final List<LogEvent> _buf = <LogEvent>[];

  List<LogEvent> snapshot() => List<LogEvent>.unmodifiable(_buf);

  @override
  Future<void> log(LogEvent event) async {
    if (capacity <= 0) return;
    if (_buf.length >= capacity) {
      _buf.removeAt(0);
    }
    _buf.add(event);
  }

  @override
  Future<void> flush() async {}

  @override
  Future<void> close() async {}
}
