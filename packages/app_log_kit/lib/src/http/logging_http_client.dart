import 'dart:async';

import 'package:http/http.dart' as http;

import '../logger/logger.dart';
import '../redaction/redactor.dart';

class LoggingHttpClient extends http.BaseClient {
  LoggingHttpClient({
    required http.Client inner,
    required Logger logger,
    Redactor? redactor,
    this.module = 'http',
    this.isHostAllowed,
    this.isPathAllowed,
  }) : _inner = inner,
       _logger = logger,
       _redactor = redactor ?? logger.redactor;

  final http.Client _inner;
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
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final started = DateTime.now();
    final rid = _logger.newRequestId();
    final uri = request.url;

    if (_allowed(uri)) {
      await _logger.debug(
        module,
        'request start',
        requestId: rid,
        ctx: <String, Object?>{
          'http': <String, Object?>{
            'method': request.method,
            'host': uri.host,
            'path': uri.path,
            'queryKeys': _redactor.redactQueryKeys(uri),
            'headers': _redactor.redactHeaders(request.headers),
          },
        },
      );
    }

    try {
      final resp = await _inner.send(request);
      final dur = DateTime.now().difference(started).inMilliseconds;
      if (_allowed(uri)) {
        final status = resp.statusCode;
        final lvl = status >= 400 ? 'warn' : 'debug';
        final ctx = <String, Object?>{
          'http': <String, Object?>{
            'method': request.method,
            'host': uri.host,
            'path': uri.path,
            'queryKeys': _redactor.redactQueryKeys(uri),
            'status': status,
            'durMs': dur,
          },
        };
        if (lvl == 'warn') {
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
      return resp;
    } catch (e, st) {
      final dur = DateTime.now().difference(started).inMilliseconds;
      if (_allowed(uri)) {
        await _logger.error(
          module,
          'request failed',
          requestId: rid,
          error: e,
          stackTrace: st,
          ctx: <String, Object?>{
            'http': <String, Object?>{
              'method': request.method,
              'host': uri.host,
              'path': uri.path,
              'queryKeys': _redactor.redactQueryKeys(uri),
              'durMs': dur,
              'errKind': _errKind(e),
            },
          },
        );
      }
      rethrow;
    }
  }

  String _errKind(Object e) {
    final s = e.toString().toLowerCase();
    if (s.contains('timeout')) return 'timeout';
    if (s.contains('dns')) return 'dns';
    if (s.contains('tls') || s.contains('handshake')) return 'tls';
    return 'http';
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }
}
