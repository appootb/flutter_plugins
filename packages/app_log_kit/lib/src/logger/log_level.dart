enum LogLevel {
  trace(10),
  debug(20),
  info(30),
  warn(40),
  error(50),
  fatal(60);

  const LogLevel(this.weight);

  final int weight;

  String get jsonName => switch (this) {
    LogLevel.trace => 'trace',
    LogLevel.debug => 'debug',
    LogLevel.info => 'info',
    LogLevel.warn => 'warn',
    LogLevel.error => 'error',
    LogLevel.fatal => 'fatal',
  };
}
