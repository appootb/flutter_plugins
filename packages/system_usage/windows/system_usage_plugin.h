#ifndef FLUTTER_PLUGIN_SYSTEM_USAGE_PLUGIN_H_
#define FLUTTER_PLUGIN_SYSTEM_USAGE_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <memory>

namespace system_usage {

class SystemUsagePlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  SystemUsagePlugin();

  virtual ~SystemUsagePlugin();

  // Disallow copy and assign.
  SystemUsagePlugin(const SystemUsagePlugin&) = delete;
  SystemUsagePlugin& operator=(const SystemUsagePlugin&) = delete;

  // Called when a method is called on this plugin's channel from Dart.
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
};

}  // namespace system_usage

#endif  // FLUTTER_PLUGIN_SYSTEM_USAGE_PLUGIN_H_
