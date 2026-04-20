
import 'file_preview_plus_platform_interface.dart';

class FilePreviewPlus {
  Future<String?> getPlatformVersion() {
    return FilePreviewPlusPlatform.instance.getPlatformVersion();
  }
}
