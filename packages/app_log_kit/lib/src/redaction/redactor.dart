import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'redaction_policy.dart';

class Redactor {
  Redactor({this.policy = const RedactionPolicy()});

  final RedactionPolicy policy;

  String truncate(String input, {int? maxLen}) {
    final limit = maxLen ?? policy.truncateStringsTo;
    if (limit <= 0) return '';
    if (input.length <= limit) return input;
    return '${input.substring(0, limit)}…';
  }

  Map<String, String> redactHeaders(Map<String, String> headers) {
    final out = <String, String>{};
    for (final entry in headers.entries) {
      final kLower = entry.key.toLowerCase();
      final isAllowed = policy.headerAllowlistLowercase.contains(kLower);
      if (!isAllowed) {
        out[entry.key] = '<redacted>';
        continue;
      }
      if (policy.redactAuthorization && kLower == 'authorization') {
        out[entry.key] = '<redacted>';
        continue;
      }
      if (policy.redactCookies &&
          (kLower == 'cookie' || kLower == 'set-cookie')) {
        out[entry.key] = '<redacted>';
        continue;
      }
      out[entry.key] = truncate(entry.value);
    }
    return out;
  }

  Uri redactUrl(Uri uri) {
    if (!policy.includeQueryKeysOnly) return uri;
    if (uri.queryParameters.isEmpty) return uri.replace(query: '');
    final keysOnly = uri.queryParameters.keys
        .map((k) => Uri.encodeQueryComponent(k))
        .join('&');
    return uri.replace(query: keysOnly);
  }

  List<String> redactQueryKeys(Uri uri) =>
      uri.queryParameters.keys.toList(growable: false);

  String redactPath(String path) {
    if (policy.includeFullPaths) return truncate(path);
    try {
      return p.basename(path);
    } catch (_) {
      return truncate(path);
    }
  }

  String sha256Hex(String input) {
    final bytes = utf8.encode(input);
    return sha256.convert(bytes).toString();
  }

  String sha256FileHex(File file) {
    final bytes = file.readAsBytesSync();
    return sha256.convert(bytes).toString();
  }
}
