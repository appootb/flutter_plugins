import 'dart:typed_data';

import 'package:advanced_clipboard/advanced_clipboard.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ClipboardContent', () {
    test('toMap uses ClipboardContentType.value', () {
      final content = ClipboardContent(
        type: ClipboardContentType.plainText,
        raw: Uint8List.fromList([1, 2, 3]),
        metadata: {'k': 'v'},
      );

      expect(content.toMap(), {
        'type': 'text',
        'raw': isA<Uint8List>(),
        'metadata': {'k': 'v'},
      });
    });

    test('fromMap accepts Uint8List raw', () {
      final raw = Uint8List.fromList([65, 66]);
      final content = ClipboardContent.fromMap({'type': 'text', 'raw': raw});

      expect(content.type, ClipboardContentType.plainText);
      expect(content.raw, raw);
      expect(content.content, 'AB');
      expect(content.metadata, isNull);
    });

    test('fromMap accepts List<int> raw', () {
      final content = ClipboardContent.fromMap({
        'type': 'text',
        'raw': [65, 66],
      });

      expect(content.type, ClipboardContentType.plainText);
      expect(content.raw, isA<Uint8List>());
      expect(content.content, 'AB');
    });

    test('fromMap coerces metadata keys to String', () {
      final content = ClipboardContent.fromMap({
        'type': 'image',
        'raw': <int>[0, 1],
        'metadata': {1: true, 'format': 'png'},
      });

      expect(content.type, ClipboardContentType.image);
      expect(content.metadata, {'1': true, 'format': 'png'});
    });
  });
}
