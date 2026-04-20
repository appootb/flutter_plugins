import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'file_preview_plus_method_channel.dart';

abstract class FilePreviewPlusPlatform extends PlatformInterface {
  /// Constructs a FilePreviewPlusPlatform.
  FilePreviewPlusPlatform() : super(token: _token);

  static final Object _token = Object();

  static FilePreviewPlusPlatform _instance = MethodChannelFilePreviewPlus();

  /// The default instance of [FilePreviewPlusPlatform] to use.
  ///
  /// Defaults to [MethodChannelFilePreviewPlus].
  static FilePreviewPlusPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [FilePreviewPlusPlatform] when
  /// they register themselves.
  static set instance(FilePreviewPlusPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
