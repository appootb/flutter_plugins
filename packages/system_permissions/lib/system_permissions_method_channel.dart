import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'src/permission_models.dart';
import 'system_permissions_platform_interface.dart';

/// An implementation of [SystemPermissionsPlatform] that uses method channels.
class MethodChannelSystemPermissions extends SystemPermissionsPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('system_permissions');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>(
      'getPlatformVersion',
    );
    return version;
  }

  @override
  Future<PermissionState> check(PermissionKind kind) async {
    final res = await methodChannel.invokeMethod<Map<Object?, Object?>>(
      'check',
      {'kind': kind.value},
    );
    final state = (res?['state'] as String?) ?? 'unknown';
    return PermissionState.fromValue(state);
  }

  @override
  Future<PermissionState> request(PermissionKind kind) async {
    final res = await methodChannel.invokeMethod<Map<Object?, Object?>>(
      'request',
      {'kind': kind.value},
    );
    final state = (res?['state'] as String?) ?? 'unknown';
    return PermissionState.fromValue(state);
  }

  @override
  Future<bool> openSystemSettings(PermissionKind kind) async {
    final res = await methodChannel.invokeMethod<Map<Object?, Object?>>(
      'openSystemSettings',
      {'kind': kind.value},
    );
    return (res?['success'] as bool?) ?? false;
  }
}
