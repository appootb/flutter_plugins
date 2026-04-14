import 'package:flutter_test/flutter_test.dart';
import 'package:system_permissions/system_permissions.dart';
import 'package:system_permissions/system_permissions_platform_interface.dart';
import 'package:system_permissions/system_permissions_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockSystemPermissionsPlatform
    with MockPlatformInterfaceMixin
    implements SystemPermissionsPlatform {
  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final SystemPermissionsPlatform initialPlatform = SystemPermissionsPlatform.instance;

  test('$MethodChannelSystemPermissions is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelSystemPermissions>());
  });

  test('getPlatformVersion', () async {
    SystemPermissions systemPermissionsPlugin = SystemPermissions();
    MockSystemPermissionsPlatform fakePlatform = MockSystemPermissionsPlatform();
    SystemPermissionsPlatform.instance = fakePlatform;

    expect(await systemPermissionsPlugin.getPlatformVersion(), '42');
  });
}
