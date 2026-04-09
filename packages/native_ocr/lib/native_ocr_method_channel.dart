import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'native_ocr_platform_interface.dart';

/// An implementation of [NativeOcrPlatform] that uses method channels.
class MethodChannelNativeOcr extends NativeOcrPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('native_ocr');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>(
      'getPlatformVersion',
    );
    return version;
  }
}
