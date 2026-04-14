// In order to *not* need this ignore, consider extracting the "web" version
// of your plugin as a separate package, instead of inlining it in the same
// package as the core of your plugin.
// ignore: avoid_web_libraries_in_flutter

import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:web/web.dart' as web;

import 'src/permission_models.dart';
import 'system_permissions_platform_interface.dart';

/// A web implementation of the SystemPermissionsPlatform of the SystemPermissions plugin.
class SystemPermissionsWeb extends SystemPermissionsPlatform {
  /// Constructs a SystemPermissionsWeb
  SystemPermissionsWeb();

  static void registerWith(Registrar registrar) {
    SystemPermissionsPlatform.instance = SystemPermissionsWeb();
  }

  /// Returns a [String] containing the version of the platform.
  @override
  Future<String?> getPlatformVersion() async {
    final version = web.window.navigator.userAgent;
    return version;
  }

  @override
  Future<PermissionState> check(PermissionKind kind) async {
    return PermissionState.unsupported;
  }

  @override
  Future<PermissionState> request(PermissionKind kind) async {
    return PermissionState.unsupported;
  }

  @override
  Future<bool> openSystemSettings(PermissionKind kind) async {
    return false;
  }
}
