#include "include/advanced_clipboard/advanced_clipboard_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "advanced_clipboard_plugin.h"

void AdvancedClipboardPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  advanced_clipboard::AdvancedClipboardPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
