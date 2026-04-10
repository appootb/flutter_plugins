
import 'system_usage_platform_interface.dart';

class SystemUsage {
  Future<String?> getPlatformVersion() {
    return SystemUsagePlatform.instance.getPlatformVersion();
  }
}
