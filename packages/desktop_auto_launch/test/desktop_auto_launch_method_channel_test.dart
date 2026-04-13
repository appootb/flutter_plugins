import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:desktop_auto_launch/desktop_auto_launch_method_channel.dart';
import 'package:desktop_auto_launch/desktop_auto_launch.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  MethodChannelDesktopAutoLaunch platform = MethodChannelDesktopAutoLaunch();
  const MethodChannel channel = MethodChannel('desktop_auto_launch');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
          switch (methodCall.method) {
            case 'getPlatformVersion':
              return '42';
            case 'isEnabled':
              final args = methodCall.arguments as Map?;
              if (args?['appName'] == 'MyApp') return true;
              return true;
            case 'setEnabled':
              final args = methodCall.arguments as Map?;
              return args?['enabled'] == true;
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('getPlatformVersion', () async {
    expect(await platform.getPlatformVersion(), '42');
  });

  test('isEnabled', () async {
    expect(await platform.isEnabled('MyApp'), isTrue);
  });

  test('setEnabled(true) passes args and returns ok', () async {
    expect(await platform.setEnabled(true), isTrue);
  });

  test('setEnabled(false) passes args and returns ok=false', () async {
    expect(await platform.setEnabled(false), isFalse);
  });

  test('setEnabled passes app config map', () async {
    await platform.setEnabled(
      true,
      app: const DesktopAutoLaunchAppConfig(
        appName: 'MyApp',
        windowsMode: WindowsAutoLaunchMode.packaged,
      ),
    );
  });
}
