import 'permission_models.dart';
import 'system_permissions_platform_interface.dart';

/// Public facade for checking/requesting common system permissions and opening
/// the relevant OS settings pages.
///
/// This package aims to provide a small, consistent API across platforms.
/// Individual [PermissionKind]s may have platform-specific behavior and
/// limitations (for example, a "request" may only trigger a system flow and
/// the final result can be delayed).
class SystemPermissions {
  Future<String?> getPlatformVersion() {
    return SystemPermissionsPlatform.instance.getPlatformVersion();
  }

  /// Checks the current permission state without showing any system UI when
  /// possible.
  Future<PermissionState> check(PermissionKind kind) {
    return SystemPermissionsPlatform.instance.check(kind);
  }

  /// Requests the permission.
  ///
  /// Depending on the platform and the [kind], this may show a system prompt,
  /// open a system settings page, or do nothing if the OS does not support a
  /// programmable request flow.
  Future<PermissionState> request(PermissionKind kind) {
    return SystemPermissionsPlatform.instance.request(kind);
  }

  /// Opens the OS settings page relevant to the [kind] (best-effort).
  ///
  /// Returns `true` if the settings UI was opened successfully.
  Future<bool> openSystemSettings(PermissionKind kind) {
    return SystemPermissionsPlatform.instance.openSystemSettings(kind);
  }
}
