import 'dart:async';

import 'package:advanced_clipboard/advanced_clipboard.dart';
import 'package:advanced_clipboard/src/method_channel.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final platform = MethodChannelAdvancedClipboard();
  const MethodChannel channel = MethodChannel('advanced_clipboard');
  const MethodChannel eventChannel = MethodChannel('advanced_clipboard_events');

  final codec = const StandardMethodCodec();

  final methodCalls = <MethodCall>[];
  StreamController<Map<dynamic, dynamic>>? eventController;

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
          methodCalls.add(methodCall);
          switch (methodCall.method) {
            case 'getPlatformVersion':
              return '42';
            case 'startListening':
              return null;
            case 'stopListening':
              return null;
            case 'write':
              return true;
          }
          return '42';
        });

    // Mock EventChannel listen/cancel.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(eventChannel, (MethodCall methodCall) async {
          if (methodCall.method == 'listen') {
            eventController = StreamController<Map<dynamic, dynamic>>();
            eventController!.stream.listen((event) {
              final data = codec.encodeSuccessEnvelope(event);
              ServicesBinding.instance.defaultBinaryMessenger
                  .handlePlatformMessage(
                    'advanced_clipboard_events',
                    data,
                    (_) {},
                  );
            });
            return null;
          }
          if (methodCall.method == 'cancel') {
            await eventController?.close();
            eventController = null;
            return null;
          }
          return null;
        });
  });

  tearDown(() {
    methodCalls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(eventChannel, null);
  });

  test('getPlatformVersion', () async {
    expect(await platform.getPlatformVersion(), '42');
  });

  test('startListening returns parsed ClipboardEntry events', () async {
    final stream = platform.startListening();

    final entryFuture = stream.first;

    eventController!.add({
      'timestamp': 1,
      'uniqueIdentifier': 'u1',
      'sourceApp': {'name': 'App', 'bundleId': 'app.exe', 'icon': null},
      'contents': [
        {
          'type': 'text',
          'raw': [65, 66],
        },
      ],
    });

    final entry = await entryFuture;
    expect(entry, isA<ClipboardEntry>());
    expect(entry.timestamp, DateTime.fromMillisecondsSinceEpoch(1));
    expect(entry.uniqueIdentifier, 'u1');
    expect(entry.sourceApp?.name, 'App');
    expect(entry.contents.single.type, ClipboardContentType.plainText);
    expect(entry.contents.single.content, 'AB');

    expect(methodCalls.any((c) => c.method == 'startListening'), isTrue);
  });

  test('stopListening invokes stopListening on method channel', () async {
    platform.startListening();
    await platform.stopListening();
    expect(methodCalls.any((c) => c.method == 'stopListening'), isTrue);
  });

  test('write sends contents list under contents key', () async {
    final ok = await platform.write([
      ClipboardContent(
        type: ClipboardContentType.url,
        raw: Uint8List.fromList([1]),
      ).toMap(),
    ]);
    expect(ok, isTrue);

    final call = methodCalls.firstWhere((c) => c.method == 'write');
    expect(call.arguments, isA<Map>());
    final args = call.arguments as Map;
    expect(args['contents'], isA<List>());
  });
}
