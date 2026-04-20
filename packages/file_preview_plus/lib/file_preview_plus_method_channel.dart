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

  @override
  Future<FileInfoMap> getFileInfo({required String path}) async {
    final raw = await methodChannel.invokeMethod<Map<Object?, Object?>>(
      'getFileInfo',
      <String, Object?>{'path': path},
    );
    if (raw == null) {
      return <String, Object?>{'path': path};
    }
    return raw.map((k, v) => MapEntry(k.toString(), v));
  }

  @override
  Future<Uint8List?> getThumbnail({
    required String path,
    int width = 256,
    int height = 256,
    int? quality,
  }) async {
    final bytes = await methodChannel.invokeMethod<Uint8List>(
      'getThumbnail',
      <String, Object?>{
        'path': path,
        'width': width,
        'height': height,
        'quality': quality,
      },
    );
    return bytes;
  }
}
