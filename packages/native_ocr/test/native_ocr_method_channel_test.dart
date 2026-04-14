import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:native_ocr/native_ocr_method_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  MethodChannelNativeOcr platform = MethodChannelNativeOcr();
  const MethodChannel channel = MethodChannel('native_ocr');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
          switch (methodCall.method) {
            case 'getPlatformVersion':
              return '42';
            case 'recognizeText':
              return 'text-from-path';
            case 'recognizeTextFromBytes':
              return 'text-from-bytes';
            default:
              return null;
          }
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('getPlatformVersion', () async {
    expect(await platform.getPlatformVersion(), '42');
  });

  test('recognizeText', () async {
    expect(await platform.recognizeText('/tmp/a.png'), 'text-from-path');
  });

  test('recognizeTextFromBytes', () async {
    expect(
      await platform.recognizeTextFromBytes(Uint8List.fromList([1, 2, 3])),
      'text-from-bytes',
    );
  });
}
