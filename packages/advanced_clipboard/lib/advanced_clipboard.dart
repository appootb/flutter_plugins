
import 'advanced_clipboard_platform_interface.dart';

class AdvancedClipboard {
  Future<String?> getPlatformVersion() {
    return AdvancedClipboardPlatform.instance.getPlatformVersion();
  }
}
