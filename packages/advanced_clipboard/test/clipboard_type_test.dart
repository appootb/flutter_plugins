import 'package:advanced_clipboard/advanced_clipboard.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ClipboardContentType', () {
    test('value is stable wire string', () {
      expect(ClipboardContentType.plainText.value, 'text');
      expect(ClipboardContentType.html.value, 'html');
      expect(ClipboardContentType.rtf.value, 'rtf');
      expect(ClipboardContentType.url.value, 'url');
      expect(ClipboardContentType.image.value, 'image');
      expect(ClipboardContentType.fileUrl.value, 'fileUrl');
      expect(ClipboardContentType.unknown.value, 'unknown');
    });

    test('fromValue maps null/unknown to unknown', () {
      expect(
        ClipboardContentType.fromValue(null),
        ClipboardContentType.unknown,
      );
      expect(
        ClipboardContentType.fromValue('does_not_exist'),
        ClipboardContentType.unknown,
      );
    });
  });
}
