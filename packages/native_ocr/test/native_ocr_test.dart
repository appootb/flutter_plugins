import 'package:flutter_test/flutter_test.dart';
import 'package:native_ocr/native_ocr.dart';
import 'package:native_ocr/native_ocr_platform_interface.dart';
import 'package:native_ocr/native_ocr_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockNativeOcrPlatform
    with MockPlatformInterfaceMixin
    implements NativeOcrPlatform {
  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final NativeOcrPlatform initialPlatform = NativeOcrPlatform.instance;

  test('$MethodChannelNativeOcr is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelNativeOcr>());
  });

  test('getPlatformVersion', () async {
    NativeOcr nativeOcrPlugin = NativeOcr();
    MockNativeOcrPlatform fakePlatform = MockNativeOcrPlatform();
    NativeOcrPlatform.instance = fakePlatform;

    expect(await nativeOcrPlugin.getPlatformVersion(), '42');
  });
}
