import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'advanced_clipboard_method_channel.dart';

abstract class AdvancedClipboardPlatform extends PlatformInterface {
  /// Constructs a AdvancedClipboardPlatform.
  AdvancedClipboardPlatform() : super(token: _token);

  static final Object _token = Object();

  static AdvancedClipboardPlatform _instance = MethodChannelAdvancedClipboard();

  /// The default instance of [AdvancedClipboardPlatform] to use.
  ///
  /// Defaults to [MethodChannelAdvancedClipboard].
  static AdvancedClipboardPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [AdvancedClipboardPlatform] when
  /// they register themselves.
  static set instance(AdvancedClipboardPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
