import 'clipboard_content.dart';
import 'source_application.dart';

/// A single clipboard snapshot emitted by the native platform.
///
/// An entry can contain multiple [ClipboardContent] items representing
/// different formats for the same clipboard change (e.g. plain text + HTML).
class ClipboardEntry {
  /// Metadata about the app that populated the clipboard, if available.
  final SourceApplication? sourceApp;

  /// Timestamp when the entry was captured on the native side.
  final DateTime timestamp;

  /// Clipboard payload in one or more formats.
  final List<ClipboardContent> contents;

  /// Platform-provided identifier for this clipboard change, if available.
  ///
  /// Currently used on Apple platforms to help de-duplicate repeated events.
  final String? uniqueIdentifier;

  const ClipboardEntry({
    this.sourceApp,
    required this.timestamp,
    required this.contents,
    this.uniqueIdentifier,
  });

  /// Creates a [ClipboardEntry] from a platform-channel map payload.
  factory ClipboardEntry.fromMap(Map<dynamic, dynamic> map) {
    final contentsList = map['contents'] as List<dynamic>?;
    final contents = contentsList != null
        ? contentsList
              .map(
                (item) =>
                    ClipboardContent.fromMap(item as Map<dynamic, dynamic>),
              )
              .toList()
        : <ClipboardContent>[];

    return ClipboardEntry(
      sourceApp: map['sourceApp'] != null
          ? SourceApplication.fromMap(map['sourceApp'] as Map<dynamic, dynamic>)
          : null,
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        (map['timestamp'] as int?) ?? DateTime.now().millisecondsSinceEpoch,
      ),
      contents: contents,
      uniqueIdentifier: map['uniqueIdentifier'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'sourceApp': sourceApp?.toMap(),
      'timestamp': timestamp.millisecondsSinceEpoch,
      'contents': contents.map((content) => content.toMap()).toList(),
      'uniqueIdentifier': uniqueIdentifier,
    };
  }
}
