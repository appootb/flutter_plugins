import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'desktop_auto_launch.dart';
import 'desktop_auto_launch_method_channel.dart';

abstract class DesktopAutoLaunchPlatform extends PlatformInterface {
  /// Constructs a DesktopAutoLaunchPlatform.
  DesktopAutoLaunchPlatform() : super(token: _token);

  static final Object _token = Object();

  static DesktopAutoLaunchPlatform _instance = MethodChannelDesktopAutoLaunch();

  /// The default instance of [DesktopAutoLaunchPlatform] to use.
  ///
  /// Defaults to [MethodChannelDesktopAutoLaunch].
  static DesktopAutoLaunchPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [DesktopAutoLaunchPlatform] when
  /// they register themselves.
  static set instance(DesktopAutoLaunchPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }

  /// Returns whether auto-launch at login is currently enabled.
  Future<bool> isEnabled(String? appName) {
    throw UnimplementedError('isEnabled() has not been implemented.');
  }

  /// Enables or disables auto-launch at login.
  Future<bool> setEnabled(
    bool enabled, {
    DesktopAutoLaunchAppConfig app = const DesktopAutoLaunchAppConfig(),
  }) {
    throw UnimplementedError('setEnabled() has not been implemented.');
  }
}
