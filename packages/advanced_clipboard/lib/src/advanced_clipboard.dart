import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'clipboard_content.dart';
import 'clipboard_content_type.dart';
import 'clipboard_entry.dart';
import 'clipboard_listener.dart';
import 'platform_interface.dart';

/// High-level API for reading and writing rich clipboard content.
///
/// This is a singleton facade over the platform implementation
/// ([AdvancedClipboardPlatform]).
class AdvancedClipboard {
  AdvancedClipboard._();

  /// Shared instance.
  static final AdvancedClipboard instance = AdvancedClipboard._();

  StreamSubscription<ClipboardEntry>? _subscription;

  /// Returns the native platform version string (mainly for diagnostics).
  Future<String?> getPlatformVersion() {
    return AdvancedClipboardPlatform.instance.getPlatformVersion();
  }

  /// Starts listening to clipboard changes.
  ///
  /// The [listener] is invoked for each clipboard change event emitted by the
  /// native platform.
  void startListening(ClipboardListener listener) {
    _subscription = AdvancedClipboardPlatform.instance.startListening().listen((
      item,
    ) {
      listener.onClipboardChanged(item);
    });
  }

  /// Stops listening to clipboard changes.
  Future<void> stopListening() async {
    await _subscription?.cancel();
    _subscription = null;
    await AdvancedClipboardPlatform.instance.stopListening();
  }

  /// Writes plain text to the clipboard.
  ///
  /// The string is encoded as UTF-8 bytes.
  Future<bool> writeText(String text) async {
    return await write([
      ClipboardContent(
        type: ClipboardContentType.plainText,
        raw: Uint8List.fromList(utf8.encode(text)),
      ),
    ]);
  }

  /// Writes HTML to the clipboard.
  ///
  /// The string is encoded as UTF-8 bytes.
  Future<bool> writeHtml(String html) async {
    return await write([
      ClipboardContent(
        type: ClipboardContentType.html,
        raw: Uint8List.fromList(utf8.encode(html)),
      ),
    ]);
  }

  /// Writes an image to the clipboard.
  ///
  /// [imageData] should contain PNG-encoded bytes.
  Future<bool> writeImage(Uint8List imageData) async {
    return await write([
      ClipboardContent(type: ClipboardContentType.image, raw: imageData),
    ]);
  }

  /// Writes a file URL to the clipboard.
  ///
  /// The file path is encoded as UTF-8 bytes and may be interpreted as a file
  /// URL by the native platform.
  Future<bool> writeFileUrl(String filePath) async {
    return await write([
      ClipboardContent(
        type: ClipboardContentType.fileUrl,
        raw: Uint8List.fromList(utf8.encode(filePath)),
      ),
    ]);
  }

  /// Writes a URL to the clipboard.
  ///
  /// The string is encoded as UTF-8 bytes.
  Future<bool> writeUrl(String url) async {
    return await write([
      ClipboardContent(
        type: ClipboardContentType.url,
        raw: Uint8List.fromList(utf8.encode(url)),
      ),
    ]);
  }

  /// Writes multiple payload variants to the clipboard in a single operation.
  ///
  /// Providing multiple [ClipboardContent] items allows native platforms to
  /// expose richer paste options (e.g. text + HTML).
  Future<bool> write(List<ClipboardContent> contents) async {
    final contentsMap = contents.map((c) => c.toMap()).toList();
    return await AdvancedClipboardPlatform.instance.write(contentsMap);
  }
}
