import 'dart:typed_data';

import 'package:advanced_clipboard/advanced_clipboard.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ClipboardEntry', () {
    test('fromMap parses timestamp/sourceApp/contents', () {
      final entry = ClipboardEntry.fromMap({
        'timestamp': 1,
        'uniqueIdentifier': 'u1',
        'sourceApp': {
          'name': 'App',
          'bundleId': 'app.exe',
          'icon': Uint8List.fromList([1, 2, 3]),
        },
        'contents': [
          {
            'type': 'text',
            'raw': [65, 66],
          },
          {
            'type': 'image',
            'raw': Uint8List.fromList([0, 1]),
            'metadata': {'format': 'png'},
          },
        ],
      });

      expect(entry.timestamp, DateTime.fromMillisecondsSinceEpoch(1));
      expect(entry.uniqueIdentifier, 'u1');
      expect(entry.sourceApp?.name, 'App');
      expect(entry.sourceApp?.bundleId, 'app.exe');
      expect(entry.sourceApp?.icon, isA<Uint8List>());
      expect(entry.contents, hasLength(2));
      expect(entry.contents[0].type, ClipboardContentType.plainText);
      expect(entry.contents[0].content, 'AB');
      expect(entry.contents[1].type, ClipboardContentType.image);
      expect(entry.contents[1].metadata, {'format': 'png'});
    });

    test('toMap round-trips timestamp and contents', () {
      final entry = ClipboardEntry(
        timestamp: DateTime.fromMillisecondsSinceEpoch(123),
        contents: [
          ClipboardContent(
            type: ClipboardContentType.url,
            raw: Uint8List.fromList('https://example.com'.codeUnits),
          ),
        ],
      );

      final map = entry.toMap();
      expect(map['timestamp'], 123);
      expect(map['sourceApp'], isNull);
      expect(map['uniqueIdentifier'], isNull);
      expect(map['contents'], isA<List>());

      final decoded = ClipboardEntry.fromMap(map);
      expect(decoded.timestamp, entry.timestamp);
      expect(decoded.contents.single.type, ClipboardContentType.url);
      expect(decoded.contents.single.content, 'https://example.com');
    });
  });
}
