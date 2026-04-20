import 'package:flutter_test/flutter_test.dart';
import 'package:file_preview_plus/file_preview_plus.dart';
import 'package:file_preview_plus/file_preview_plus_platform_interface.dart';
import 'package:file_preview_plus/file_preview_plus_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockFilePreviewPlusPlatform
    with MockPlatformInterfaceMixin
    implements FilePreviewPlusPlatform {
  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final FilePreviewPlusPlatform initialPlatform = FilePreviewPlusPlatform.instance;

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
