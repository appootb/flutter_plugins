import '../logger/log_event.dart';

abstract class LogSink {
  Future<void> log(LogEvent event);

  Future<void> flush();

  Future<void> close();
}
