#include "include/file_preview_plus/file_preview_plus_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "file_preview_plus_plugin.h"

void FilePreviewPlusPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  file_preview_plus::FilePreviewPlusPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
