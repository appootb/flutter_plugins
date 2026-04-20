import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'file_preview_plus_platform_interface.dart';

/// An implementation of [FilePreviewPlusPlatform] that uses method channels.
class MethodChannelFilePreviewPlus extends FilePreviewPlusPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('file_preview_plus');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>(
      'getPlatformVersion',
    );
    return version;
  }
}
