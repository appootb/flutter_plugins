import 'package:flutter_test/flutter_test.dart';
import 'package:advanced_clipboard/advanced_clipboard.dart';
import 'package:advanced_clipboard/advanced_clipboard_platform_interface.dart';
import 'package:advanced_clipboard/advanced_clipboard_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockAdvancedClipboardPlatform
    with MockPlatformInterfaceMixin
    implements AdvancedClipboardPlatform {
  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final AdvancedClipboardPlatform initialPlatform = AdvancedClipboardPlatform.instance;

  test('$MethodChannelAdvancedClipboard is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelAdvancedClipboard>());
  });

  test('getPlatformVersion', () async {
    AdvancedClipboard advancedClipboardPlugin = AdvancedClipboard();
    MockAdvancedClipboardPlatform fakePlatform = MockAdvancedClipboardPlatform();
    AdvancedClipboardPlatform.instance = fakePlatform;

    expect(await advancedClipboardPlugin.getPlatformVersion(), '42');
  });
}
