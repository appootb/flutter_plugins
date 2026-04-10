import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'system_usage_platform_interface.dart';

/// An implementation of [SystemUsagePlatform] that uses method channels.
class MethodChannelSystemUsage extends SystemUsagePlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('system_usage');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>(
      'getPlatformVersion',
    );
    return version;
  }
}
