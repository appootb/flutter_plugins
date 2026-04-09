import 'clipboard_entry.dart';

/// Listener interface for clipboard change events.
abstract mixin class ClipboardListener {
  /// Called when a new [ClipboardEntry] is received from the native platform.
  ///
  /// Implementations should return quickly; heavy work should be offloaded.
  void onClipboardChanged(ClipboardEntry entry);
}
