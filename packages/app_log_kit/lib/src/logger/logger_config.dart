import 'log_level.dart';

class LoggerConfig {
  LoggerConfig({
    this.level = LogLevel.info,
    Map<String, LogLevel>? moduleLevels,
    this.enableDebugLogging = false,
    this.maxStringLength = 2048,
    this.sampleRate = 1.0,
    Map<String, double>? moduleSampleRatesOverrides,
    this.rateLimitWindow,
    this.rateLimitMaxPerKey = 0,
  }) : moduleLevels = moduleLevels ?? <String, LogLevel>{},
       moduleSampleRates = moduleSampleRatesOverrides ?? <String, double>{};

  LogLevel level;
  final Map<String, LogLevel> moduleLevels;

  /// Convenience toggle: when false, anything below [LogLevel.info] is suppressed.
  /// (You can still use per-module overrides if you want.)
  bool enableDebugLogging;

  /// Safety: truncate strings inside log payloads to avoid bloat.
  int maxStringLength;

  /// Sampling rate in range (0, 1]. 1.0 = no sampling.
  /// Applied after level filtering, before sinks.
  double sampleRate;

  /// Per-module sampling rates override [sampleRate] when present.
  final Map<String, double> moduleSampleRates;

  /// Rate limit window. When set and [rateLimitMaxPerKey] > 0,
  /// suppresses repeated logs with the same key within the window.
  Duration? rateLimitWindow;

  /// Maximum logs allowed per key per [rateLimitWindow].
  /// Set to 0 to disable rate limiting.
  int rateLimitMaxPerKey;

  LogLevel effectiveLevelForModule(String module) {
    final perModule = moduleLevels[module];
    if (perModule != null) return perModule;
    if (!enableDebugLogging && level.weight < LogLevel.info.weight) {
      return LogLevel.info;
    }
    return level;
  }

  double effectiveSampleRateForModule(String module) {
    final r = moduleSampleRates[module];
    if (r != null) return r;
    return sampleRate;
  }
}
