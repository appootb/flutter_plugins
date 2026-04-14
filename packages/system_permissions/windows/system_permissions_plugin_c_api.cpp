#include "include/system_permissions/system_permissions_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "system_permissions_plugin.h"

void SystemPermissionsPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  system_permissions::SystemPermissionsPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
