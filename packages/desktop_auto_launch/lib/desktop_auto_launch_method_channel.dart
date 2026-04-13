import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'desktop_auto_launch.dart';
import 'desktop_auto_launch_platform_interface.dart';

/// An implementation of [DesktopAutoLaunchPlatform] that uses method channels.
class MethodChannelDesktopAutoLaunch extends DesktopAutoLaunchPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('desktop_auto_launch');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>(
      'getPlatformVersion',
    );
    return version;
  }

  @override
  Future<bool> isEnabled(String? appName) async {
    final enabled = await methodChannel.invokeMethod<bool>(
      'isEnabled',
      appName == null ? null : {'appName': appName},
    );
    return enabled ?? false;
  }

  @override
  Future<bool> setEnabled(
    bool enabled, {
    DesktopAutoLaunchAppConfig app = const DesktopAutoLaunchAppConfig(),
  }) async {
    final ok = await methodChannel.invokeMethod<bool>('setEnabled', {
      'enabled': enabled,
      'app': app.toMap(),
    });
    return ok ?? false;
  }
}
