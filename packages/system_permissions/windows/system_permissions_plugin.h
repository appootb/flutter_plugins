#ifndef FLUTTER_PLUGIN_SYSTEM_PERMISSIONS_PLUGIN_H_
#define FLUTTER_PLUGIN_SYSTEM_PERMISSIONS_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <memory>

namespace system_permissions {

class SystemPermissionsPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  SystemPermissionsPlugin();

  virtual ~SystemPermissionsPlugin();

  // Disallow copy and assign.
  SystemPermissionsPlugin(const SystemPermissionsPlugin&) = delete;
  SystemPermissionsPlugin& operator=(const SystemPermissionsPlugin&) = delete;

  // Called when a method is called on this plugin's channel from Dart.
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
};

}  // namespace system_permissions

#endif  // FLUTTER_PLUGIN_SYSTEM_PERMISSIONS_PLUGIN_H_
