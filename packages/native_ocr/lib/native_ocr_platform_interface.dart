import 'dart:typed_data';

import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'native_ocr_method_channel.dart';

abstract class NativeOcrPlatform extends PlatformInterface {
  /// Constructs a NativeOcrPlatform.
  NativeOcrPlatform() : super(token: _token);

  static final Object _token = Object();

  static NativeOcrPlatform _instance = MethodChannelNativeOcr();

  /// The default instance of [NativeOcrPlatform] to use.
  ///
  /// Defaults to [MethodChannelNativeOcr].
  static NativeOcrPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [NativeOcrPlatform] when
  /// they register themselves.
  static set instance(NativeOcrPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }

  Future<String?> recognizeText(
    String imagePath, {
    List<String>? languageCodes,
  }) {
    throw UnimplementedError('recognizeText() has not been implemented.');
  }

  Future<String?> recognizeTextFromBytes(
    Uint8List imageBytes, {
    List<String>? languageCodes,
  }) {
    throw UnimplementedError(
      'recognizeTextFromBytes() has not been implemented.',
    );
  }
}
