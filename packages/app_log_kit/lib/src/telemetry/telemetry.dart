abstract class ErrorReporter {
  const ErrorReporter();

  Future<void> report({
    required Object error,
    StackTrace? stackTrace,
    Map<String, Object?>? context,
  });
}

class NoopErrorReporter extends ErrorReporter {
  const NoopErrorReporter();

  @override
  Future<void> report({
    required Object error,
    StackTrace? stackTrace,
    Map<String, Object?>? context,
  }) async {}
}

class CompositeErrorReporter extends ErrorReporter {
  const CompositeErrorReporter(this.reporters);

  final List<ErrorReporter> reporters;

  @override
  Future<void> report({
    required Object error,
    StackTrace? stackTrace,
    Map<String, Object?>? context,
  }) async {
    for (final r in reporters) {
      try {
        await r.report(error: error, stackTrace: stackTrace, context: context);
      } catch (_) {
        // Best-effort: never throw from reporter.
      }
    }
  }
}
