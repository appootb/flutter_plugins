import 'dart:convert';
import 'dart:typed_data';

import 'clipboard_content_type.dart';

/// One clipboard payload variant within a [ClipboardEntry].
///
/// Native platforms may provide the same clipboard change in multiple formats
/// (e.g. plain text + HTML). This class carries the raw bytes and optional
/// metadata for a specific [ClipboardContentType].
class ClipboardContent {
  /// The semantic type of this payload.
  final ClipboardContentType type;

  /// Raw bytes as provided by the native platform (often UTF-8 for text).
  final Uint8List? _raw;

  /// Optional metadata attached by the native layer.
  final Map<String, dynamic>? metadata;

  ClipboardContent._internal({
    required this.type,
    required Uint8List? raw,
    Map<String, dynamic>? metadata,
  }) : _raw = raw,
       metadata = metadata == null
           ? null
           : Map.unmodifiable(Map<String, dynamic>.from(metadata));

  factory ClipboardContent({
    required ClipboardContentType type,
    Uint8List? raw,
    Map<String, dynamic>? metadata,
  }) {
    return ClipboardContent._internal(type: type, raw: raw, metadata: metadata);
  }

  /// Creates a [ClipboardContent] from a platform-channel map payload.
  ///
  /// The `raw` field may be sent as a [Uint8List] or as a `List<int>`.
  factory ClipboardContent.fromMap(Map<dynamic, dynamic> map) {
    final type = _parseDataType(map['type'] as String?);
    final meta = map['metadata'];
    Map<String, dynamic>? metadata;
    if (meta is Map) {
      metadata = meta.map((key, value) => MapEntry(key.toString(), value));
    }

    // Convert raw data to Uint8List
    Uint8List? rawData;
    final raw = map['raw'];
    if (raw != null) {
      if (raw is Uint8List) {
        rawData = raw;
      } else if (raw is List) {
        rawData = Uint8List.fromList(raw.cast<int>());
      }
    }

    return ClipboardContent._internal(
      type: type,
      raw: rawData,
      metadata: metadata,
    );
  }

  /// Raw payload bytes.
  Uint8List? get raw => _raw;

  /// Decodes [raw] as UTF-8 text.
  ///
  /// Returns `null` if [raw] is absent or cannot be decoded.
  String? get content {
    final raw = _raw;
    if (raw == null) return null;
    try {
      // Use allowMalformed to handle incomplete UTF-8 sequences
      // This is important for clipboard data that may contain malformed bytes
      return utf8.decode(raw, allowMalformed: true);
    } catch (_) {
      return null;
    }
  }

  /// Serializes this instance to a map suitable for platform channels / JSON.
  Map<String, dynamic> toMap() {
    return {'type': type.value, 'raw': _raw, 'metadata': metadata};
  }

  static ClipboardContentType _parseDataType(String? type) =>
      ClipboardContentType.fromValue(type);
}
