import 'dart:typed_data';

import 'native_ocr_platform_interface.dart';

/// A cross-platform native OCR wrapper.
///
/// This plugin exposes a single, unified API surface on the Dart side and
/// delegates the actual OCR work to each platform's native implementation:
/// - iOS/macOS: Apple Vision
/// - Android: Google ML Kit Text Recognition
/// - Windows: Windows.Media.Ocr
/// - Linux: Tesseract (optional; returns UNAVAILABLE when missing)
///
/// ## Language selection
/// [languageCodes] is a list of BCP-47 language tags (e.g. `en-US`, `zh-Hans`).
/// - If provided and non-empty, it is passed to the native side.
/// - Otherwise, the plugin falls back to the current system locales, then to
///   `en-US` if nothing is available.
/// - When multiple languages are present, English (`en-*`) is moved to the end
///   of the list so non-English languages take priority when supported.
///
/// Note: platform support differs. For example, Android's default ML Kit
/// recognizer may not fully honor language hints depending on the model.
class NativeOcr {
  Future<String?> getPlatformVersion() {
    return NativeOcrPlatform.instance.getPlatformVersion();
  }

  /// Recognize text from an image file path.
  ///
  /// [imagePath] must be a readable local file path on the current platform.
  /// Returns the recognized plain text (possibly empty).
  Future<String?> recognizeText(
    String imagePath, {
    List<String>? languageCodes,
  }) {
    return NativeOcrPlatform.instance.recognizeText(
      imagePath,
      languageCodes: languageCodes,
    );
  }

  /// Recognize text from encoded image bytes (e.g. PNG/JPEG file bytes).
  ///
  /// [imageBytes] must contain the full image file bytes.
  /// Returns the recognized plain text (possibly empty).
  Future<String?> recognizeTextFromBytes(
    Uint8List imageBytes, {
    List<String>? languageCodes,
  }) {
    return NativeOcrPlatform.instance.recognizeTextFromBytes(
      imageBytes,
      languageCodes: languageCodes,
    );
  }
}
