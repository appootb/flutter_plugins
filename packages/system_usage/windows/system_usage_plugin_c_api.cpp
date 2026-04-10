#include "include/system_usage/system_usage_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "system_usage_plugin.h"

void SystemUsagePluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  system_usage::SystemUsagePlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
