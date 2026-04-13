import 'package:flutter_test/flutter_test.dart';
import 'package:desktop_auto_launch/desktop_auto_launch.dart';
import 'package:desktop_auto_launch/desktop_auto_launch_platform_interface.dart';
import 'package:desktop_auto_launch/desktop_auto_launch_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockDesktopAutoLaunchPlatform
    with MockPlatformInterfaceMixin
    implements DesktopAutoLaunchPlatform {
  @override
  Future<String?> getPlatformVersion() => Future.value('42');

  @override
  Future<bool> isEnabled(String? appName) => Future.value(true);

  @override
  Future<bool> setEnabled(
    bool enabled, {
    DesktopAutoLaunchAppConfig app = const DesktopAutoLaunchAppConfig(),
  }) =>
      Future.value(enabled);
}

void main() {
  final DesktopAutoLaunchPlatform initialPlatform = DesktopAutoLaunchPlatform.instance;

  test('$MethodChannelDesktopAutoLaunch is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelDesktopAutoLaunch>());
  });

  test('getPlatformVersion', () async {
    MockDesktopAutoLaunchPlatform fakePlatform = MockDesktopAutoLaunchPlatform();
    DesktopAutoLaunchPlatform.instance = fakePlatform;

    expect(await DesktopAutoLaunch.instance.getPlatformVersion(), '42');
  });

  test('isEnabled', () async {
    final fakePlatform = MockDesktopAutoLaunchPlatform();
    DesktopAutoLaunchPlatform.instance = fakePlatform;
    expect(await DesktopAutoLaunch.instance.isEnabled('MyApp'), isTrue);
  });

  test('setEnabled forwards to platform', () async {
    final fakePlatform = MockDesktopAutoLaunchPlatform();
    DesktopAutoLaunchPlatform.instance = fakePlatform;

    expect(await DesktopAutoLaunch.instance.setEnabled(true), isTrue);
    expect(await DesktopAutoLaunch.instance.setEnabled(false), isFalse);
  });
}
