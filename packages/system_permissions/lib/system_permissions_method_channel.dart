import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

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
}
