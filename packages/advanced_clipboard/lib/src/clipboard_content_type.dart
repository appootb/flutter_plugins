/// Enumerates clipboard payload types supported by this plugin.
///
/// The [value] is the stable string representation used for platform channels
/// and serialization.
enum ClipboardContentType {
  unknown('unknown'),
  plainText('text'),
  html('html'),
  rtf('rtf'),
  url('url'),
  image('image'),
  fileUrl('fileUrl'),
  mixed('mixed');

  const ClipboardContentType(this.value);

  /// The string representation used for platform channels / serialization.
  final String value;

  /// Parses a string [value] into a [ClipboardContentType].
  ///
  /// Unknown or `null` values map to [ClipboardContentType.unknown].
  static ClipboardContentType fromValue(String? value) {
    switch (value) {
      case 'text':
        return ClipboardContentType.plainText;
      case 'html':
        return ClipboardContentType.html;
      case 'rtf':
        return ClipboardContentType.rtf;
      case 'url':
        return ClipboardContentType.url;
      case 'image':
        return ClipboardContentType.image;
      case 'fileUrl':
        return ClipboardContentType.fileUrl;
      case 'mixed':
        return ClipboardContentType.mixed;
      default:
        return ClipboardContentType.unknown;
    }
  }
}
