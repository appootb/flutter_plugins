
import 'desktop_auto_launch_platform_interface.dart';

/// Windows startup registration mode.
///
/// - [auto]: let the native layer decide the best strategy.
/// - [packaged]: for MSIX/Store packaged apps.
/// - [unpackaged]: for classic Win32 apps.
enum WindowsAutoLaunchMode { auto, packaged, unpackaged }

/// App identity/configuration used by native startup registration.
///
/// macOS (ServiceManagement / SMAppService.mainApp) does **not** need these
/// fields (the system uses the current app bundle). Windows/Linux typically do.
class DesktopAutoLaunchAppConfig {
  /// Application name used for OS-level registration.
  ///
  /// - Windows: used as the startup entry name (best-effort).
  ///   - Unpackaged (Win32): used as the `Run` registry value name.
  ///   - Packaged (MSIX/Store): used to derive the StartupTask id.
  ///     Convention: `taskId = "${appName}Startup"`.
  ///     The app's MSIX/Appx manifest must declare a `startupTask` with the
  ///     exact same `taskId`, otherwise StartupTask APIs will fail.
  /// - Linux: used as the `.desktop` file name / entry name (best-effort).
  final String? appName;

  /// Windows: packaged vs unpackaged behavior selection.
  final WindowsAutoLaunchMode windowsMode;

  const DesktopAutoLaunchAppConfig({
    this.appName,
    this.windowsMode = WindowsAutoLaunchMode.auto,
  });

  Map<String, dynamic> toMap() => {
        'appName': appName,
        'windowsMode': windowsMode.name,
      };
}

class DesktopAutoLaunch {
  DesktopAutoLaunch._();

  static final DesktopAutoLaunch instance = DesktopAutoLaunch._();

  Future<String?> getPlatformVersion() {
    return DesktopAutoLaunchPlatform.instance.getPlatformVersion();
  }

  /// Returns whether auto-launch at login is currently enabled for this app.
  ///
  /// On Linux, [appName] is used to locate the autostart desktop file:
  /// `~/.config/autostart/<appName>.desktop`.
  ///
  /// On macOS, this parameter is ignored (SMAppService.mainApp).
  Future<bool> isEnabled(String? appName) {
    return DesktopAutoLaunchPlatform.instance.isEnabled(appName);
  }

  /// Enables or disables auto-launch at login for this app.
  ///
  /// [app] is ignored on macOS (SMAppService.mainApp). Windows/Linux may use it.
  Future<bool> setEnabled(
    bool enabled, {
    DesktopAutoLaunchAppConfig app = const DesktopAutoLaunchAppConfig(),
  }) {
    return DesktopAutoLaunchPlatform.instance.setEnabled(
      enabled,
      app: app,
    );
  }
}
