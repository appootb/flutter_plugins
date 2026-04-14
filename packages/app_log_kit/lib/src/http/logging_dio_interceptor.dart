import 'package:dio/dio.dart';

import '../logger/logger.dart';
import '../redaction/redactor.dart';

class LoggingDioInterceptor extends Interceptor {
  LoggingDioInterceptor({
    required Logger logger,
    Redactor? redactor,
    this.module = 'http',
    this.isHostAllowed,
    this.isPathAllowed,
  }) : _logger = logger,
       _redactor = redactor ?? logger.redactor;

  final Logger _logger;
  final Redactor _redactor;
  final String module;
  final bool Function(String host)? isHostAllowed;
  final bool Function(String path)? isPathAllowed;

  bool _allowed(Uri uri) {
    if (isHostAllowed != null && !isHostAllowed!(uri.host)) return false;
    if (isPathAllowed != null && !isPathAllowed!(uri.path)) return false;
    return true;
  }

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final uri = options.uri;
    if (_allowed(uri)) {
      final rid = _logger.newRequestId();
      options.extra['app_log_kit_rid'] = rid;
      options.extra['app_log_kit_started_ms'] =
          DateTime.now().millisecondsSinceEpoch;
      await _logger.debug(
        module,
        'request start',
        requestId: rid,
        ctx: <String, Object?>{
          'http': <String, Object?>{
            'method': options.method,
            'host': uri.host,
            'path': uri.path,
            'queryKeys': _redactor.redactQueryKeys(uri),
            'headers': _redactor.redactHeaders(
              options.headers.map((k, v) => MapEntry(k, '$v')),
            ),
          },
        },
      );
    }
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) async {
    final uri = response.requestOptions.uri;
    if (_allowed(uri)) {
      final started =
          (response.requestOptions.extra['app_log_kit_started_ms'] as int?) ??
          DateTime.now().millisecondsSinceEpoch;
      final durMs = DateTime.now().millisecondsSinceEpoch - started;
      final rid = response.requestOptions.extra['app_log_kit_rid'] as String?;
      final status = response.statusCode ?? 0;
      final ctx = <String, Object?>{
        'http': <String, Object?>{
          'method': response.requestOptions.method,
          'host': uri.host,
          'path': uri.path,
          'queryKeys': _redactor.redactQueryKeys(uri),
          'status': status,
          'durMs': durMs,
        },
      };
      if (status >= 400) {
        await _logger.warn(
          module,
          'request complete',
          requestId: rid,
          ctx: ctx,
        );
      } else {
        await _logger.debug(
          module,
          'request complete',
          requestId: rid,
          ctx: ctx,
        );
      }
    }
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final uri = err.requestOptions.uri;
    if (_allowed(uri)) {
      final started =
          (err.requestOptions.extra['app_log_kit_started_ms'] as int?) ??
          DateTime.now().millisecondsSinceEpoch;
      final durMs = DateTime.now().millisecondsSinceEpoch - started;
      final rid = err.requestOptions.extra['app_log_kit_rid'] as String?;
      await _logger.error(
        module,
        'request failed',
        requestId: rid,
        error: err,
        stackTrace: err.stackTrace,
        ctx: <String, Object?>{
          'http': <String, Object?>{
            'method': err.requestOptions.method,
            'host': uri.host,
            'path': uri.path,
            'queryKeys': _redactor.redactQueryKeys(uri),
            'durMs': durMs,
            'errKind': _errKind(err),
            'status': err.response?.statusCode,
          },
        },
      );
    }
    handler.next(err);
  }

  String _errKind(DioException e) {
    return switch (e.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout => 'timeout',
      DioExceptionType.badCertificate => 'tls',
      DioExceptionType.connectionError => 'dns',
      DioExceptionType.badResponse => 'http',
      DioExceptionType.cancel => 'cancel',
      DioExceptionType.unknown => 'http',
    };
  }
}
