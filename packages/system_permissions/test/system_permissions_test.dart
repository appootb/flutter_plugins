import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:system_permissions/permission_models.dart';
import 'package:system_permissions/system_permissions.dart';
import 'package:system_permissions/system_permissions_method_channel.dart';
import 'package:system_permissions/system_permissions_platform_interface.dart';

class MockSystemPermissionsPlatform
    with MockPlatformInterfaceMixin
    implements SystemPermissionsPlatform {
  @override
  Future<String?> getPlatformVersion() => Future.value('42');

  @override
  Future<PermissionState> check(PermissionKind kind) => Future.value(
    kind == PermissionKind.accessibility
        ? PermissionState.granted
        : PermissionState.unsupported,
  );

  @override
  Future<PermissionState> request(PermissionKind kind) => Future.value(
    kind == PermissionKind.accessibility
        ? PermissionState.denied
        : PermissionState.unsupported,
  );

  @override
  Future<bool> openSystemSettings(PermissionKind kind) => Future.value(true);
}

void main() {
  final SystemPermissionsPlatform initialPlatform =
      SystemPermissionsPlatform.instance;

  test('$MethodChannelSystemPermissions is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelSystemPermissions>());
  });

  test('getPlatformVersion', () async {
    SystemPermissions systemPermissionsPlugin = SystemPermissions();
    MockSystemPermissionsPlatform fakePlatform =
        MockSystemPermissionsPlatform();
    SystemPermissionsPlatform.instance = fakePlatform;

    expect(await systemPermissionsPlugin.getPlatformVersion(), '42');
  });

  test('check/request/openSystemSettings delegate to platform', () async {
    SystemPermissions systemPermissionsPlugin = SystemPermissions();
    MockSystemPermissionsPlatform fakePlatform =
        MockSystemPermissionsPlatform();
    SystemPermissionsPlatform.instance = fakePlatform;

    expect(
      await systemPermissionsPlugin.check(PermissionKind.accessibility),
      PermissionState.granted,
    );
    expect(
      await systemPermissionsPlugin.request(PermissionKind.accessibility),
      PermissionState.denied,
    );
    expect(
      await systemPermissionsPlugin.openSystemSettings(
        PermissionKind.accessibility,
      ),
      true,
    );
  });
}
