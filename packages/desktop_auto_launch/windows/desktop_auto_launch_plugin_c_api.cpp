#include "include/desktop_auto_launch/desktop_auto_launch_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "desktop_auto_launch_plugin.h"

void DesktopAutoLaunchPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  desktop_auto_launch::DesktopAutoLaunchPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
