import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:system_usage/system_usage_method_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  MethodChannelSystemUsage platform = MethodChannelSystemUsage();
  const MethodChannel channel = MethodChannel('system_usage');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
          return '42';
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('getPlatformVersion', () async {
    expect(await platform.getPlatformVersion(), '42');
  });

  test('getSnapshot', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
          if (methodCall.method == 'getSnapshot') {
            return <String, dynamic>{
              'timestampMs': 1,
              'cpu': <String, dynamic>{'coreCount': 8, 'usage': 0.5},
              'memory': <String, dynamic>{
                'totalBytes': 100,
                'usedBytes': 60,
                'freeBytes': 40,
                'wiredBytes': 10,
              },
            };
          }
          return '42';
        });

    final snap = await platform.getSnapshot();
    expect(snap?['timestampMs'], 1);
    expect((snap?['cpu'] as Map)['coreCount'], 8);
  });
}
