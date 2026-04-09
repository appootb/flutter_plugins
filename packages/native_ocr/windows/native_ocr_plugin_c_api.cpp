#include "include/native_ocr/native_ocr_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "native_ocr_plugin.h"

void NativeOcrPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  native_ocr::NativeOcrPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
