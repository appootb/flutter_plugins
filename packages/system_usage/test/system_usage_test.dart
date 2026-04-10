import 'package:flutter_test/flutter_test.dart';
import 'package:system_usage/system_usage.dart';
import 'package:system_usage/system_usage_platform_interface.dart';
import 'package:system_usage/system_usage_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockSystemUsagePlatform
    with MockPlatformInterfaceMixin
    implements SystemUsagePlatform {
  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final SystemUsagePlatform initialPlatform = SystemUsagePlatform.instance;

  test('$MethodChannelSystemUsage is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelSystemUsage>());
  });

  test('getPlatformVersion', () async {
    SystemUsage systemUsagePlugin = SystemUsage();
    MockSystemUsagePlatform fakePlatform = MockSystemUsagePlatform();
    SystemUsagePlatform.instance = fakePlatform;

    expect(await systemUsagePlugin.getPlatformVersion(), '42');
  });
}
