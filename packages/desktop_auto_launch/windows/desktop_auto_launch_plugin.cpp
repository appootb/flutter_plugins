#include "desktop_auto_launch_plugin.h"

// This must be included before many other Windows headers.
#include <windows.h>

// Packaged app detection.
#include <appmodel.h>

// For getPlatformVersion; remove unless needed for your plugin implementation.
#include <VersionHelpers.h>

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <winrt/Windows.ApplicationModel.h>
#include <winrt/Windows.Foundation.h>

#include <memory>
#include <sstream>
#include <string>
#include <optional>

namespace desktop_auto_launch {

namespace {

using flutter::EncodableMap;
using flutter::EncodableValue;

bool IsPackagedApp() {
  UINT32 length = 0;
  const LONG rc = GetCurrentPackageFullName(&length, nullptr);
  return rc != APPMODEL_ERROR_NO_PACKAGE;
}

std::optional<std::string> GetString(const EncodableMap& map,
                                     const char* key) {
  auto it = map.find(EncodableValue(key));
  if (it == map.end()) return std::nullopt;
  if (!std::holds_alternative<std::string>(it->second)) return std::nullopt;
  return std::get<std::string>(it->second);
}

std::optional<bool> GetBool(const EncodableMap& map, const char* key) {
  auto it = map.find(EncodableValue(key));
  if (it == map.end()) return std::nullopt;
  if (!std::holds_alternative<bool>(it->second)) return std::nullopt;
  return std::get<bool>(it->second);
}

std::optional<EncodableMap> GetMap(const EncodableMap& map, const char* key) {
  auto it = map.find(EncodableValue(key));
  if (it == map.end()) return std::nullopt;
  if (!std::holds_alternative<EncodableMap>(it->second)) return std::nullopt;
  return std::get<EncodableMap>(it->second);
}

std::wstring Utf8ToWide(const std::string& s) {
  if (s.empty()) return L"";
  const int len = MultiByteToWideChar(CP_UTF8, 0, s.c_str(), -1, nullptr, 0);
  std::wstring out(len, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, s.c_str(), -1, out.data(), len);
  if (!out.empty() && out.back() == L'\0') out.pop_back();
  return out;
}

std::wstring GetCurrentExePath() {
  std::wstring path(MAX_PATH, L'\0');
  DWORD size = GetModuleFileNameW(nullptr, path.data(),
                                 static_cast<DWORD>(path.size()));
  if (size == 0) return L"";
  path.resize(size);
  return path;
}

bool RegistrySetRunValue(const std::wstring& name, const std::wstring& value,
                         std::string* error_out) {
  HKEY key = nullptr;
  const LONG rc = RegCreateKeyExW(
      HKEY_CURRENT_USER,
      L"Software\\Microsoft\\Windows\\CurrentVersion\\Run",
      0, nullptr, 0, KEY_SET_VALUE, nullptr, &key, nullptr);
  if (rc != ERROR_SUCCESS) {
    if (error_out) *error_out = "RegCreateKeyExW failed.";
    return false;
  }
  const DWORD bytes = static_cast<DWORD>((value.size() + 1) * sizeof(wchar_t));
  const LONG set_rc =
      RegSetValueExW(key, name.c_str(), 0, REG_SZ,
                     reinterpret_cast<const BYTE*>(value.c_str()), bytes);
  RegCloseKey(key);
  if (set_rc != ERROR_SUCCESS) {
    if (error_out) *error_out = "RegSetValueExW failed.";
    return false;
  }
  return true;
}

bool RegistryDeleteRunValue(const std::wstring& name, std::string* error_out) {
  HKEY key = nullptr;
  const LONG rc = RegOpenKeyExW(
      HKEY_CURRENT_USER,
      L"Software\\Microsoft\\Windows\\CurrentVersion\\Run",
      0, KEY_SET_VALUE, &key);
  if (rc == ERROR_FILE_NOT_FOUND) {
    return true;
  }
  if (rc != ERROR_SUCCESS) {
    if (error_out) *error_out = "RegOpenKeyExW failed.";
    return false;
  }
  const LONG del_rc = RegDeleteValueW(key, name.c_str());
  RegCloseKey(key);
  if (del_rc == ERROR_FILE_NOT_FOUND) {
    return true;
  }
  if (del_rc != ERROR_SUCCESS) {
    if (error_out) *error_out = "RegDeleteValueW failed.";
    return false;
  }
  return true;
}

bool RegistryHasRunValue(const std::wstring& name) {
  HKEY key = nullptr;
  const LONG rc = RegOpenKeyExW(
      HKEY_CURRENT_USER,
      L"Software\\Microsoft\\Windows\\CurrentVersion\\Run",
      0, KEY_QUERY_VALUE, &key);
  if (rc != ERROR_SUCCESS) return false;

  DWORD type = 0;
  DWORD bytes = 0;
  const LONG qrc =
      RegQueryValueExW(key, name.c_str(), nullptr, &type, nullptr, &bytes);
  RegCloseKey(key);
  return qrc == ERROR_SUCCESS;
}

}  // namespace

// static
void DesktopAutoLaunchPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows *registrar) {
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), "desktop_auto_launch",
          &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<DesktopAutoLaunchPlugin>();

  channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto &call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });

  registrar->AddPlugin(std::move(plugin));
}

DesktopAutoLaunchPlugin::DesktopAutoLaunchPlugin() {}

DesktopAutoLaunchPlugin::~DesktopAutoLaunchPlugin() {}

void DesktopAutoLaunchPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue> &method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (method_call.method_name().compare("getPlatformVersion") == 0) {
    std::ostringstream version_stream;
    version_stream << "Windows ";
    if (IsWindows10OrGreater()) {
      version_stream << "10+";
    } else if (IsWindows8OrGreater()) {
      version_stream << "8";
    } else if (IsWindows7OrGreater()) {
      version_stream << "7";
    }
    result->Success(flutter::EncodableValue(version_stream.str()));
  } else if (method_call.method_name().compare("isEnabled") == 0) {
    // For unpackaged: registry Run key presence.
    // For packaged: StartupTask state.
    try {
      std::wstring key_name;
      const auto* args_val = method_call.arguments();
      if (args_val != nullptr && std::holds_alternative<EncodableMap>(*args_val)) {
        const auto args = std::get<EncodableMap>(*args_val);
        const auto app_name_opt = GetString(args, "appName");
        if (app_name_opt.has_value() && !app_name_opt->empty()) {
          key_name = Utf8ToWide(*app_name_opt);
        }
      }
      if (key_name.empty()) {
        // Default key name: executable file name.
        std::wstring exe = GetCurrentExePath();
        const auto pos = exe.find_last_of(L"\\/");
        key_name = (pos == std::wstring::npos) ? exe : exe.substr(pos + 1);
      }

      const bool packaged = IsPackagedApp();
      if (packaged) {
        winrt::init_apartment();
        // MSIX StartupTask id convention:
        // taskId = "<appName>Startup"
        // This must match the startupTask.taskId declared in the app's MSIX/Appx manifest.
        const std::wstring task_id = key_name + L"Startup";
        const auto task =
            winrt::Windows::ApplicationModel::StartupTask::GetAsync(task_id)
                .get();
        const auto state = task.State();
        const bool enabled =
            state == winrt::Windows::ApplicationModel::StartupTaskState::Enabled ||
            state == winrt::Windows::ApplicationModel::StartupTaskState::EnabledByPolicy;
        result->Success(EncodableValue(enabled));
      } else {
        result->Success(EncodableValue(RegistryHasRunValue(key_name)));
      }
    } catch (const std::exception& e) {
      result->Error("AUTO_START_ERROR", "Failed to query auto-start state.",
                    EncodableValue(std::string(e.what())));
    }
  } else if (method_call.method_name().compare("setEnabled") == 0) {
    const auto* args_val = method_call.arguments();
    if (args_val == nullptr || !std::holds_alternative<EncodableMap>(*args_val)) {
      result->Error("INVALID_ARGUMENT", "Missing arguments.");
      return;
    }
    const auto args = std::get<EncodableMap>(*args_val);
    const auto enabled_opt = GetBool(args, "enabled");
    if (!enabled_opt.has_value()) {
      result->Error("INVALID_ARGUMENT", "Missing `enabled`.");
      return;
    }
    const bool enabled = enabled_opt.value();

    const auto app_opt = GetMap(args, "app");
    EncodableMap app_map;
    if (app_opt.has_value()) {
      app_map = app_opt.value();
    }

    const auto app_name_opt = GetString(app_map, "appName");
    if (!app_name_opt.has_value() || app_name_opt->empty()) {
      result->Error("INVALID_ARGUMENT", "Missing `app.appName`.");
      return;
    }
    const std::wstring app_name = Utf8ToWide(*app_name_opt);

    const auto windows_mode_opt = GetString(app_map, "windowsMode");
    const std::string windows_mode =
        windows_mode_opt.has_value() ? *windows_mode_opt : "auto";

    const bool packaged = IsPackagedApp();
    const bool use_packaged =
        windows_mode == "packaged" ? true
        : windows_mode == "unpackaged" ? false
        : packaged;  // auto

    if (use_packaged) {
      // Packaged (MSIX/Store): StartupTask.
      try {
        winrt::init_apartment();
        // MSIX StartupTask id convention:
        // taskId = "<appName>Startup"
        // This must match the startupTask.taskId declared in the app's MSIX/Appx manifest.
        const std::wstring task_id = app_name + L"Startup";
        const auto task =
            winrt::Windows::ApplicationModel::StartupTask::GetAsync(task_id)
                .get();
        if (enabled) {
          const auto state = task.RequestEnableAsync().get();
          const bool ok =
              state == winrt::Windows::ApplicationModel::StartupTaskState::Enabled ||
              state == winrt::Windows::ApplicationModel::StartupTaskState::EnabledByPolicy;
          result->Success(EncodableValue(ok));
        } else {
          task.Disable();
          result->Success(EncodableValue(true));
        }
      } catch (const std::exception& e) {
        result->Error("AUTO_START_ERROR",
                      "Failed to update StartupTask auto-start state.",
                      EncodableValue(std::string(e.what())));
      }
      return;
    }

    // Unpackaged (Win32): registry Run key.
    const std::wstring exe_path = GetCurrentExePath();
    if (exe_path.empty()) {
      result->Error("REGISTRY_ERROR", "Failed to resolve executable path.");
      return;
    }
    std::string error;
    const bool ok = enabled
                        ? RegistrySetRunValue(app_name, exe_path, &error)
                        : RegistryDeleteRunValue(app_name, &error);
    if (!ok) {
      result->Error("REGISTRY_ERROR", error);
      return;
    }
    result->Success(EncodableValue(true));
  } else {
    result->NotImplemented();
  }
}

}  // namespace desktop_auto_launch
