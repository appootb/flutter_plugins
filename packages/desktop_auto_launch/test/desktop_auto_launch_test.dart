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
}

void main() {
  final DesktopAutoLaunchPlatform initialPlatform = DesktopAutoLaunchPlatform.instance;

  test('$MethodChannelDesktopAutoLaunch is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelDesktopAutoLaunch>());
  });

  test('getPlatformVersion', () async {
    DesktopAutoLaunch desktopAutoLaunchPlugin = DesktopAutoLaunch();
    MockDesktopAutoLaunchPlatform fakePlatform = MockDesktopAutoLaunchPlatform();
    DesktopAutoLaunchPlatform.instance = fakePlatform;

    expect(await desktopAutoLaunchPlugin.getPlatformVersion(), '42');
  });
}
