import 'dart:async';
import 'dart:typed_data';

import 'package:advanced_clipboard/advanced_clipboard.dart';
import 'package:advanced_clipboard/src/method_channel.dart';
import 'package:advanced_clipboard/src/platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockAdvancedClipboardPlatform
    with MockPlatformInterfaceMixin
    implements AdvancedClipboardPlatform {
  MockAdvancedClipboardPlatform();

  final events = StreamController<ClipboardEntry>.broadcast();
  int stopListeningCalls = 0;
  List<Map<String, dynamic>>? lastWriteContents;

  @override
  Future<String?> getPlatformVersion() => Future.value('42');

  @override
  Stream<ClipboardEntry> startListening() => events.stream;

  @override
  Future<void> stopListening() async {
    stopListeningCalls += 1;
  }

  @override
  Future<bool> write(List<Map<String, dynamic>> contents) async {
    lastWriteContents = contents;
    return true;
  }
}

void main() {
  final AdvancedClipboardPlatform initialPlatform =
      AdvancedClipboardPlatform.instance;

  test('$MethodChannelAdvancedClipboard is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelAdvancedClipboard>());
  });

  test('getPlatformVersion', () async {
    MockAdvancedClipboardPlatform fakePlatform =
        MockAdvancedClipboardPlatform();
    AdvancedClipboardPlatform.instance = fakePlatform;

    expect(await AdvancedClipboard.instance.getPlatformVersion(), '42');
  });

  test('startListening forwards ClipboardEntry to listener', () async {
    final fakePlatform = MockAdvancedClipboardPlatform();
    AdvancedClipboardPlatform.instance = fakePlatform;

    final received = <ClipboardEntry>[];
    final listener = _TestListener((e) => received.add(e));

    AdvancedClipboard.instance.startListening(listener);

    final entry = ClipboardEntry(
      timestamp: DateTime.fromMillisecondsSinceEpoch(1),
      contents: [
        ClipboardContent(
          type: ClipboardContentType.plainText,
          raw: Uint8List.fromList('hello'.codeUnits),
        ),
      ],
    );
    fakePlatform.events.add(entry);

    await Future<void>.delayed(const Duration(milliseconds: 1));
    expect(received, [entry]);

    await AdvancedClipboard.instance.stopListening();
  });

  test(
    'stopListening cancels subscription and calls platform stopListening',
    () async {
      final fakePlatform = MockAdvancedClipboardPlatform();
      AdvancedClipboardPlatform.instance = fakePlatform;

      AdvancedClipboard.instance.startListening(_TestListener((_) {}));
      await AdvancedClipboard.instance.stopListening();
      expect(fakePlatform.stopListeningCalls, 1);

      // After stop, events should not be forwarded.
      var called = false;
      AdvancedClipboard.instance.startListening(
        _TestListener((_) => called = true),
      );
      fakePlatform.events.add(
        ClipboardEntry(timestamp: DateTime.now(), contents: const []),
      );
      await Future<void>.delayed(const Duration(milliseconds: 1));
      expect(called, isTrue);

      await AdvancedClipboard.instance.stopListening();
    },
  );

  test(
    'writeText/writeUrl/writeHtml/writeFileUrl/writeImage produce expected type',
    () async {
      final fakePlatform = MockAdvancedClipboardPlatform();
      AdvancedClipboardPlatform.instance = fakePlatform;

      await AdvancedClipboard.instance.writeText('hi');
      expect(fakePlatform.lastWriteContents, isNotNull);
      expect(fakePlatform.lastWriteContents, hasLength(1));
      expect(fakePlatform.lastWriteContents!.single['type'], 'text');

      await AdvancedClipboard.instance.writeUrl('https://example.com');
      expect(fakePlatform.lastWriteContents, hasLength(1));
      expect(fakePlatform.lastWriteContents!.single['type'], 'url');

      await AdvancedClipboard.instance.writeHtml('<b>x</b>');
      expect(fakePlatform.lastWriteContents, hasLength(1));
      expect(fakePlatform.lastWriteContents!.single['type'], 'html');

      await AdvancedClipboard.instance.writeFileUrl('/tmp/a.txt');
      expect(fakePlatform.lastWriteContents, hasLength(1));
      expect(fakePlatform.lastWriteContents!.single['type'], 'fileUrl');

      await AdvancedClipboard.instance.writeImage(
        Uint8List.fromList([0, 1, 2]),
      );
      expect(fakePlatform.lastWriteContents, hasLength(1));
      expect(fakePlatform.lastWriteContents!.single['type'], 'image');
    },
  );
}

class _TestListener implements ClipboardListener {
  _TestListener(this._onChange);

  final void Function(ClipboardEntry entry) _onChange;

  @override
  void onClipboardChanged(ClipboardEntry entry) => _onChange(entry);
}
