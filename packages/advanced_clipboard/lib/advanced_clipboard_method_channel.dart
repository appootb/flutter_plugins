import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'advanced_clipboard_platform_interface.dart';

/// An implementation of [AdvancedClipboardPlatform] that uses method channels.
class MethodChannelAdvancedClipboard extends AdvancedClipboardPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('advanced_clipboard');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>(
      'getPlatformVersion',
    );
    return version;
  }
}
