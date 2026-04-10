import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'system_usage_method_channel.dart';

abstract class SystemUsagePlatform extends PlatformInterface {
  /// Constructs a SystemUsagePlatform.
  SystemUsagePlatform() : super(token: _token);

  static final Object _token = Object();

  static SystemUsagePlatform _instance = MethodChannelSystemUsage();

  /// The default instance of [SystemUsagePlatform] to use.
  ///
  /// Defaults to [MethodChannelSystemUsage].
  static SystemUsagePlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [SystemUsagePlatform] when
  /// they register themselves.
  static set instance(SystemUsagePlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
