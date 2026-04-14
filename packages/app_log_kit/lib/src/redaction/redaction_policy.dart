class RedactionPolicy {
  const RedactionPolicy({
    this.redactAuthorization = true,
    this.redactCookies = true,
    this.headerAllowlistLowercase = const <String>{
      'accept',
      'accept-language',
      'content-type',
      'user-agent',
      'x-request-id',
      'x-correlation-id',
    },
    this.truncateStringsTo = 2048,
    this.includeQueryKeysOnly = true,
    this.includeFullPaths = false,
  });

  final bool redactAuthorization;
  final bool redactCookies;

  /// If set, only headers in this set are included; all others become `<redacted>`.
  final Set<String> headerAllowlistLowercase;

  final int truncateStringsTo;

  /// When true, URLs are logged without values for query params (keys only).
  final bool includeQueryKeysOnly;

  /// When false, file paths are reduced to basename only.
  final bool includeFullPaths;
}
