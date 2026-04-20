import 'dart:typed_data';

import 'package:file_preview_plus/file_preview_plus.dart';
import 'package:file_preview_plus/file_preview_plus_method_channel.dart';
import 'package:file_preview_plus/file_preview_plus_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockFilePreviewPlusPlatform
    with MockPlatformInterfaceMixin
    implements FilePreviewPlusPlatform {
  @override
  Future<String?> getPlatformVersion() => Future.value('42');

  @override
  Future<FileInfoMap> getFileInfo({required String path}) =>
      Future.value(<String, Object?>{'path': path});

  @override
  Future<Uint8List?> getThumbnail({
    required String path,
    int width = 256,
    int height = 256,
    int? quality,
  }) => Future.value(null);
}

void main() {
  final FilePreviewPlusPlatform initialPlatform =
      FilePreviewPlusPlatform.instance;

  test('$MethodChannelFilePreviewPlus is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelFilePreviewPlus>());
  });

  test('getPlatformVersion', () async {
    FilePreviewPlus filePreviewPlusPlugin = FilePreviewPlus();
    MockFilePreviewPlusPlatform fakePlatform = MockFilePreviewPlusPlatform();
    FilePreviewPlusPlatform.instance = fakePlatform;

    expect(await filePreviewPlusPlugin.getPlatformVersion(), '42');
  });
}
