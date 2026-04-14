import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'src/permission_models.dart';
import 'system_permissions_method_channel.dart';

abstract class SystemPermissionsPlatform extends PlatformInterface {
  /// Constructs a SystemPermissionsPlatform.
  SystemPermissionsPlatform() : super(token: _token);

  static final Object _token = Object();

  static SystemPermissionsPlatform _instance = MethodChannelSystemPermissions();

  /// The default instance of [SystemPermissionsPlatform] to use.
  ///
  /// Defaults to [MethodChannelSystemPermissions].
  static SystemPermissionsPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [SystemPermissionsPlatform] when
  /// they register themselves.
  static set instance(SystemPermissionsPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }

  Future<PermissionState> check(PermissionKind kind) {
    throw UnimplementedError('check() has not been implemented.');
  }

  Future<PermissionState> request(PermissionKind kind) {
    throw UnimplementedError('request() has not been implemented.');
  }

  Future<bool> openSystemSettings(PermissionKind kind) {
    throw UnimplementedError('openSystemSettings() has not been implemented.');
  }
}
