import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'native_ocr_platform_interface.dart';

/// An implementation of [NativeOcrPlatform] that uses method channels.
class MethodChannelNativeOcr extends NativeOcrPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('native_ocr');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>(
      'getPlatformVersion',
    );
    return version;
  }

  @override
  Future<String?> recognizeText(
    String imagePath, {
    List<String>? languageCodes,
  }) async {
    final effectiveLanguageCodes = _effectiveLanguageCodes(languageCodes);
    final text = await methodChannel.invokeMethod<String>(
      'recognizeText',
      <String, Object?>{
        'imagePath': imagePath,
        'languageCodes': effectiveLanguageCodes,
      },
    );
    return text;
  }

  @override
  Future<String?> recognizeTextFromBytes(
    Uint8List imageBytes, {
    List<String>? languageCodes,
  }) async {
    final effectiveLanguageCodes = _effectiveLanguageCodes(languageCodes);
    final text = await methodChannel.invokeMethod<String>(
      'recognizeTextFromBytes',
      <String, Object?>{
        'imageBytes': imageBytes,
        'languageCodes': effectiveLanguageCodes,
      },
    );
    return text;
  }
}

List<String> _effectiveLanguageCodes(List<String>? languageCodes) {
  final normalized = <String>[];

  void addAll(Iterable<String> codes) {
    for (final raw in codes) {
      final n = _normalizeLanguageCode(raw);
      if (n == null) continue;
      normalized.add(n);
    }
  }

  if (languageCodes != null && languageCodes.isNotEmpty) {
    addAll(languageCodes);
  } else {
    final locales = PlatformDispatcher.instance.locales;
    addAll(locales.map((l) => l.toLanguageTag()));
  }

  if (normalized.isEmpty) {
    normalized.add('en-US');
  }

  // De-dup, stable.
  final seen = <String>{};
  final deduped = <String>[];
  for (final code in normalized) {
    final key = code.toLowerCase();
    if (seen.add(key)) {
      deduped.add(code);
    }
  }

  // Stable move English to end (only when there's more than one language).
  if (deduped.length <= 1) return deduped;
  final nonEn = <String>[];
  final en = <String>[];
  for (final code in deduped) {
    if (_isEnglishLanguageCode(code)) {
      en.add(code);
    } else {
      nonEn.add(code);
    }
  }
  if (nonEn.isEmpty) return deduped;
  return <String>[...nonEn, ...en];
}

String? _normalizeLanguageCode(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  // Locale strings are sometimes underscore separated.
  final normalized = trimmed.replaceAll('_', '-');
  return normalized;
}

bool _isEnglishLanguageCode(String code) {
  final c = code.toLowerCase();
  return c == 'en' || c.startsWith('en-');
}
