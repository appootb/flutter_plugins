import 'dart:typed_data';

/// Metadata about the application that produced the current clipboard entry.
///
/// Availability and fields may vary by platform. When not available, values
/// can be `null`.
class SourceApplication {
  /// Best-effort source application name as reported by the native platform.
  ///
  /// Typical values by platform:
  /// - macOS: the app display name (e.g. "Safari").
  /// - Windows: the app name derived from the active process executable
  ///   metadata/path (e.g. a display name from the exe).
  /// - Linux (X11): the active window process name from `/proc/<pid>/comm`
  ///   (e.g. "gnome-shell").
  final String? name;

  /// Best-effort application identifier as reported by the native platform.
  ///
  /// Typical values by platform:
  /// - macOS: bundle identifier (e.g. "com.apple.Safari").
  /// - Windows: the active process executable file name (e.g. "notepad.exe").
  /// - Linux (X11): the active window executable path from `/proc/<pid>/exe`
  ///   (e.g. "/usr/bin/gnome-terminal").
  final String? bundleId;

  /// Application icon as PNG-encoded bytes, if available.
  final Uint8List? icon;

  const SourceApplication({this.name, this.bundleId, this.icon});

  /// Creates a [SourceApplication] from a platform-channel map payload.
  ///
  /// The `icon` field may be sent as a [Uint8List] or as a `List<int>`.
  factory SourceApplication.fromMap(Map<dynamic, dynamic> map) {
    Uint8List? icon;
    final iconData = map['icon'];
    if (iconData != null) {
      if (iconData is Uint8List) {
        icon = iconData;
      } else if (iconData is List) {
        icon = Uint8List.fromList(iconData.cast<int>());
      }
    }
    return SourceApplication(
      name: map['name'] as String?,
      bundleId: map['bundleId'] as String?,
      icon: icon,
    );
  }

  /// Serializes this instance to a map suitable for platform channels / JSON.
  Map<String, dynamic> toMap() {
    return {'name': name, 'bundleId': bundleId, 'icon': icon};
  }
}
