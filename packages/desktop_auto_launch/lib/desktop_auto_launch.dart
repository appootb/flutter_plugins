
import 'desktop_auto_launch_platform_interface.dart';

class DesktopAutoLaunch {
  Future<String?> getPlatformVersion() {
    return DesktopAutoLaunchPlatform.instance.getPlatformVersion();
  }
}
