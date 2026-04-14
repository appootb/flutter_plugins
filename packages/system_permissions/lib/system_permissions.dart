
import 'system_permissions_platform_interface.dart';

class SystemPermissions {
  Future<String?> getPlatformVersion() {
    return SystemPermissionsPlatform.instance.getPlatformVersion();
  }
}
