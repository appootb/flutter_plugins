
import 'native_ocr_platform_interface.dart';

class NativeOcr {
  Future<String?> getPlatformVersion() {
    return NativeOcrPlatform.instance.getPlatformVersion();
  }
}
