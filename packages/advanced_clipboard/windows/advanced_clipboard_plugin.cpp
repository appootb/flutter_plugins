#include "advanced_clipboard_plugin.h"

// This must be included before many other Windows headers.
#include <windows.h>
#include <ole2.h>
#include <shlobj.h>
#include <shellapi.h>
#include <psapi.h>
#include <commctrl.h>
#include <gdiplus.h>
#include <VersionHelpers.h>

#include <flutter/event_channel.h>
#include <flutter/event_stream_handler_functions.h>
#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <memory>
#include <sstream>
#include <chrono>
#include <algorithm>
#include <regex>

#pragma comment(lib, "gdiplus.lib")
#pragma comment(lib, "ole32.lib")
#pragma comment(lib, "version.lib")
#pragma comment(lib, "shell32.lib")

namespace advanced_clipboard {

// Static instance pointer for WinEventProc callback
AdvancedClipboardPlugin* AdvancedClipboardPlugin::instance_ = nullptr;

// Clipboard format constants
const UINT AdvancedClipboardPlugin::CF_HTML = RegisterClipboardFormatA("HTML Format");
const UINT AdvancedClipboardPlugin::CF_RTF = RegisterClipboardFormatA("Rich Text Format");

// static
void AdvancedClipboardPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows *registrar) {
  // Initialize COM for clipboard operations
  OleInitialize(NULL);

  auto method_channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), "advanced_clipboard",
          &flutter::StandardMethodCodec::GetInstance());

  auto event_channel =
      std::make_unique<flutter::EventChannel<flutter::EncodableValue>>(
          registrar->messenger(), "advanced_clipboard_events",
          &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<AdvancedClipboardPlugin>();
  plugin->method_channel_ = std::move(method_channel);
  plugin->event_channel_ = std::move(event_channel);

  plugin->method_channel_->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto &call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });

  plugin->event_channel_->SetStreamHandler(
      std::make_unique<flutter::StreamHandlerFunctions<flutter::EncodableValue>>(
          [plugin_pointer = plugin.get()](
              const flutter::EncodableValue* arguments,
              std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>&& events)
              -> std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>> {
            if (events) {
              plugin_pointer->event_sink_ = std::move(events);
              plugin_pointer->StartMonitoring();
            }
            return nullptr;
          },
          [plugin_pointer = plugin.get()](
              const flutter::EncodableValue* arguments)
              -> std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>> {
            plugin_pointer->StopMonitoring();
            plugin_pointer->event_sink_.reset();
            return nullptr;
          }));

  registrar->AddPlugin(std::move(plugin));
}

AdvancedClipboardPlugin::AdvancedClipboardPlugin() {
  // Set static instance pointer
  instance_ = this;

  // Initialize GDI+
  Gdiplus::GdiplusStartupInput gdiplusStartupInput;
  Gdiplus::GdiplusStartup(&gdiplus_token_, &gdiplusStartupInput, NULL);

  // Create a message-only window for clipboard notifications
  WNDCLASSW wc = {};
  wc.lpfnWndProc = WndProc;
  wc.hInstance = GetModuleHandle(NULL);
  wc.lpszClassName = L"AdvancedClipboardPluginWindow";

  if (RegisterClassW(&wc)) {
    hwnd_ = CreateWindowExW(0, wc.lpszClassName, L"", 0, 0, 0, 0, 0,
                           HWND_MESSAGE, NULL, GetModuleHandle(NULL), this);
  }

  // Initialize cached app info with current foreground window
  HWND hwnd = GetForegroundWindow();
  if (hwnd && IsValidUserAppWindow(hwnd)) {
    UpdateCachedAppInfo(hwnd);
  }
}

AdvancedClipboardPlugin::~AdvancedClipboardPlugin() {
  StopMonitoring();
  if (hwnd_) {
    DestroyWindow(hwnd_);
  }
  // Clear static instance pointer
  if (instance_ == this) {
    instance_ = nullptr;
  }

  // Shutdown GDI+
  Gdiplus::GdiplusShutdown(gdiplus_token_);

  OleUninitialize();
}

void AdvancedClipboardPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue> &method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const auto& method_name = method_call.method_name();

  if (method_name.compare("getPlatformVersion") == 0) {
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
  } else if (method_name.compare("startListening") == 0) {
    StartMonitoring();
    result->Success();
  } else if (method_name.compare("stopListening") == 0) {
    StopMonitoring();
    result->Success();
  } else if (method_name.compare("write") == 0) {
    const auto* arguments = method_call.arguments();
    if (arguments && std::holds_alternative<flutter::EncodableMap>(*arguments)) {
      const auto& args_map = std::get<flutter::EncodableMap>(*arguments);
      auto contents_it = args_map.find(flutter::EncodableValue("contents"));
      if (contents_it != args_map.end() &&
          std::holds_alternative<std::vector<flutter::EncodableValue>>(contents_it->second)) {
        const auto& contents_list = std::get<std::vector<flutter::EncodableValue>>(contents_it->second);
        std::vector<flutter::EncodableMap> contents;
        for (const auto& item : contents_list) {
          if (std::holds_alternative<flutter::EncodableMap>(item)) {
            contents.push_back(std::get<flutter::EncodableMap>(item));
          }
        }
        bool success = WriteToClipboard(contents);
        result->Success(flutter::EncodableValue(success));
        return;
      }
    }
    result->Success(flutter::EncodableValue(false));
  } else {
    result->NotImplemented();
  }
}

// StreamHandler implementation
// Window procedure
LRESULT CALLBACK AdvancedClipboardPlugin::WndProc(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
  if (message == WM_CREATE) {
    SetWindowLongPtr(hwnd, GWLP_USERDATA, (LONG_PTR)((CREATESTRUCT*)lparam)->lpCreateParams);
    return 0;
  }

  AdvancedClipboardPlugin* plugin = (AdvancedClipboardPlugin*)GetWindowLongPtr(hwnd, GWLP_USERDATA);
  if (plugin) {
    return plugin->HandleWindowMessage(hwnd, message, wparam, lparam);
  }

  return DefWindowProc(hwnd, message, wparam, lparam);
}

LRESULT AdvancedClipboardPlugin::HandleWindowMessage(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
  if (message == WM_CLIPBOARDUPDATE) {
    CheckClipboardChange();
    return 0;
  }
  return DefWindowProc(hwnd, message, wparam, lparam);
}

// Utility function to check if window is a valid user app window
bool AdvancedClipboardPlugin::IsValidUserAppWindow(HWND hwnd) {
  if (!IsWindow(hwnd)) return false;
  if (!IsWindowVisible(hwnd)) return false;

  // Exclude tool windows
  LONG_PTR exStyle = GetWindowLongPtr(hwnd, GWL_EXSTYLE);
  if (exStyle & WS_EX_TOOLWINDOW) return false;

  // Exclude windows without title (most overlays)
  wchar_t title[2];
  GetWindowTextW(hwnd, title, 2);
  if (wcslen(title) == 0) return false;

  return true;
}

// Screenshot tool process name whitelist
static const std::vector<std::string> screenshot_tool_processes = {
  "Weixin.exe",
  "QQ.exe",
  "DingTalk.exe",
  "Feishu.exe",
  "Lark.exe",
  "Telegram.exe",
  "Slack.exe",
  "SnippingTool.exe",
  "ScreenClippingHost.exe",
  "ShareX.exe",
  "Greenshot.exe",
  "Flameshot.exe",
};

// Check if window is fullscreen (with tolerance)
bool AdvancedClipboardPlugin::IsWindowFullscreen(HWND hwnd) {
  if (!hwnd) return false;

  // Check if window is maximized
  WINDOWPLACEMENT wp = {};
  wp.length = sizeof(WINDOWPLACEMENT);
  if (GetWindowPlacement(hwnd, &wp)) {
    if (wp.showCmd == SW_SHOWMAXIMIZED) {
      return true;
    }
  }

  RECT windowRect;
  if (!GetWindowRect(hwnd, &windowRect)) return false;

  // Get monitor that contains the window
  HMONITOR hMonitor = MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST);
  if (!hMonitor) {
    // Fallback to primary screen
    int screenWidth = GetSystemMetrics(SM_CXSCREEN);
    int screenHeight = GetSystemMetrics(SM_CYSCREEN);
    int windowWidth = windowRect.right - windowRect.left;
    int windowHeight = windowRect.bottom - windowRect.top;

    const int tolerance = 10;
    bool widthMatch = (windowWidth >= screenWidth - tolerance) && (windowWidth <= screenWidth + tolerance);
    bool heightMatch = (windowHeight >= screenHeight - tolerance) && (windowHeight <= screenHeight + tolerance);
    return widthMatch && heightMatch;
  }

  // Get monitor info
  MONITORINFO monitorInfo = {};
  monitorInfo.cbSize = sizeof(MONITORINFO);
  if (!GetMonitorInfo(hMonitor, &monitorInfo)) return false;

  int monitorWidth = monitorInfo.rcMonitor.right - monitorInfo.rcMonitor.left;
  int monitorHeight = monitorInfo.rcMonitor.bottom - monitorInfo.rcMonitor.top;
  int windowWidth = windowRect.right - windowRect.left;
  int windowHeight = windowRect.bottom - windowRect.top;

  // Allow 10 pixel tolerance
  const int tolerance = 10;
  bool widthMatch = (windowWidth >= monitorWidth - tolerance) && (windowWidth <= monitorWidth + tolerance);
  bool heightMatch = (windowHeight >= monitorHeight - tolerance) && (windowHeight <= monitorHeight + tolerance);

  // Also check if window position matches monitor position (within tolerance)
  bool xMatch = (windowRect.left >= monitorInfo.rcMonitor.left - tolerance) && 
                (windowRect.left <= monitorInfo.rcMonitor.left + tolerance);
  bool yMatch = (windowRect.top >= monitorInfo.rcMonitor.top - tolerance) && 
                (windowRect.top <= monitorInfo.rcMonitor.top + tolerance);

  return widthMatch && heightMatch && xMatch && yMatch;
}

// Check if window is borderless or layered
bool AdvancedClipboardPlugin::IsWindowBorderlessOrLayered(HWND hwnd) {
  if (!hwnd) return false;

  LONG_PTR exStyle = GetWindowLongPtr(hwnd, GWL_EXSTYLE);
  LONG_PTR style = GetWindowLongPtr(hwnd, GWL_STYLE);

  // Check for layered window (WS_EX_LAYERED)
  bool isLayered = (exStyle & WS_EX_LAYERED) != 0;

  // Check for borderless window (no WS_CAPTION, WS_THICKFRAME, WS_SYSMENU)
  bool isBorderless = !(style & WS_CAPTION) && !(style & WS_THICKFRAME) && !(style & WS_SYSMENU);

  return isLayered || isBorderless;
}

// Check if window is transparent
bool AdvancedClipboardPlugin::IsWindowTransparent(HWND hwnd) {
  if (!hwnd) return false;

  LONG_PTR exStyle = GetWindowLongPtr(hwnd, GWL_EXSTYLE);
  
  // Check if window has WS_EX_LAYERED style
  if (!(exStyle & WS_EX_LAYERED)) {
    return false;
  }

  // Get window transparency (alpha value)
  BYTE alpha = 255;
  DWORD flags = 0;
  if (GetLayeredWindowAttributes(hwnd, nullptr, &alpha, &flags)) {
    // If alpha is less than 255, window is transparent
    if (alpha < 255) {
      return true;
    }
    // Check if LWA_ALPHA flag is set
    if (flags & LWA_ALPHA) {
      return true;
    }
  }

  return false;
}

// Check if process is a screenshot tool based on process name and window characteristics
bool AdvancedClipboardPlugin::IsScreenshotTool(HWND hwnd, const std::string& processName) {
  if (!hwnd || processName.empty()) return false;

  // Convert process name to lowercase for case-insensitive comparison
  std::string processNameLower = processName;
  std::transform(processNameLower.begin(), processNameLower.end(), processNameLower.begin(),
                 [](unsigned char c) { return static_cast<char>(std::tolower(c)); });

  // Check if process name is in whitelist
  bool inWhitelist = false;
  for (const auto& tool : screenshot_tool_processes) {
    std::string toolLower = tool;
    std::transform(toolLower.begin(), toolLower.end(), toolLower.begin(),
                   [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
    if (processNameLower == toolLower) {
      inWhitelist = true;
      break;
    }
  }

  if (!inWhitelist) {
    return false;
  }

  // Check the three conditions
  bool isFullscreen = IsWindowFullscreen(hwnd);
  bool isBorderlessOrLayered = IsWindowBorderlessOrLayered(hwnd);
  bool isTransparent = IsWindowTransparent(hwnd);

  // Count how many conditions are met
  int conditionCount = 0;
  if (isFullscreen) conditionCount++;
  if (isBorderlessOrLayered) conditionCount++;
  if (isTransparent) conditionCount++;

  // If 2 or more conditions are met, consider it a screenshot tool
  return conditionCount >= 2;
}

// WinEventProc callback for foreground window changes
void CALLBACK AdvancedClipboardPlugin::WinEventProc(
    HWINEVENTHOOK hWinEventHook,
    DWORD event,
    HWND hwnd,
    LONG idObject,
    LONG idChild,
    DWORD dwEventThread,
    DWORD dwmsTimeStamp) {
  if (event == EVENT_SYSTEM_FOREGROUND && instance_ && hwnd) {
    if (IsValidUserAppWindow(hwnd)) {
      // Get process name to check if it's a screenshot tool
      DWORD process_id;
      GetWindowThreadProcessId(hwnd, &process_id);
      std::string processName = (process_id > 0 && instance_) 
        ? instance_->GetProcessName(process_id) 
        : "";

      // Skip screenshot tools
      if (!processName.empty() && IsScreenshotTool(hwnd, processName)) {
        return;
      }

      instance_->UpdateCachedAppInfo(hwnd);
    }
  }
}

// Update cached app info from window handle
void AdvancedClipboardPlugin::UpdateCachedAppInfo(HWND hwnd) {
  cached_app_info_.clear();

  if (!hwnd || !IsValidUserAppWindow(hwnd)) {
    return;
  }

  // Get process ID
  DWORD process_id;
  GetWindowThreadProcessId(hwnd, &process_id);
  if (process_id == 0) {
    return;
  }

  // Get exe path
  std::wstring exePath = GetProcessExePath(process_id);
  if (exePath.empty()) {
    return;
  }

  // Get app name from exe file
  std::string appName = GetAppNameFromExe(exePath);
  if (!appName.empty()) {
    cached_app_info_[flutter::EncodableValue("name")] = flutter::EncodableValue(appName);
  }

  // Get process name (exe filename) as bundleId
  std::string processName = GetProcessName(process_id);
  if (!processName.empty()) {
    cached_app_info_[flutter::EncodableValue("bundleId")] = flutter::EncodableValue(processName);
  }

  // Get app icon and convert to PNG
  HICON hIcon = GetAppIcon(exePath);
  if (hIcon) {
    std::vector<uint8_t> iconPng;
    if (IconToPNG(hIcon, iconPng) && !iconPng.empty()) {
      cached_app_info_[flutter::EncodableValue("icon")] = flutter::EncodableValue(iconPng);
    }
    DestroyIcon(hIcon);
  }
}

// Monitoring methods
void AdvancedClipboardPlugin::StartMonitoring() {
  if (is_listening_) return;

  if (AddClipboardFormatListener(hwnd_)) {
    is_listening_ = true;
    last_clipboard_sequence_ = GetClipboardSequenceNumber();
  }

  // Set up WinEventHook for foreground window tracking
  if (!win_event_hook_) {
    win_event_hook_ = SetWinEventHook(
        EVENT_SYSTEM_FOREGROUND,
        EVENT_SYSTEM_FOREGROUND,
        NULL,
        WinEventProc,
        0,
        0,
        WINEVENT_OUTOFCONTEXT);
  }
}

void AdvancedClipboardPlugin::StopMonitoring() {
  // Remove clipboard format listener
  if (is_listening_) {
    RemoveClipboardFormatListener(hwnd_);
    is_listening_ = false;
  }

  // Remove WinEventHook
  if (win_event_hook_) {
    UnhookWinEvent(win_event_hook_);
    win_event_hook_ = nullptr;
  }
}

void AdvancedClipboardPlugin::CheckClipboardChange() {
  DWORD current_sequence = GetClipboardSequenceNumber();
  if (current_sequence == last_clipboard_sequence_) return;

  last_clipboard_sequence_ = current_sequence;

  // If we intentionally wrote to clipboard, ignore this next change
  if (ignore_next_change_) {
    ignore_next_change_ = false;
    return;
  }

  // Small delay to allow clipboard data to stabilize
  // This helps with timing issues when clipboard is rapidly updated
  Sleep(10); // 10ms delay

  // Compose entry and send to Dart
  // ExtractContentsWithRetry already handles retry logic
  if (event_sink_) {
    try {
      auto entry = CreateClipboardEntry(current_sequence);
      event_sink_->Success(flutter::EncodableValue(entry));
    } catch (...) {
      // If clipboard access fails completely, we can't do much
      // This might happen if clipboard is locked by another process
    }
  }
}

// Clipboard operations
flutter::EncodableMap AdvancedClipboardPlugin::CreateClipboardEntry(DWORD sequence_number) {
  int64_t timestamp = std::chrono::duration_cast<std::chrono::milliseconds>(
      std::chrono::system_clock::now().time_since_epoch()).count();

  auto source_app = SerializeAppInfo();
  auto contents = ExtractContentsWithRetry();

  flutter::EncodableMap entry;
  entry[flutter::EncodableValue("timestamp")] = flutter::EncodableValue(timestamp);
  entry[flutter::EncodableValue("sourceApp")] = flutter::EncodableValue(source_app);
  entry[flutter::EncodableValue("contents")] = flutter::EncodableValue(contents);
  entry[flutter::EncodableValue("uniqueIdentifier")] = flutter::EncodableValue(std::to_string(sequence_number));

  return entry;
}

flutter::EncodableList AdvancedClipboardPlugin::ExtractContentsWithRetry() {
  const int maxRetries = 3;
  flutter::EncodableList result;

  for (int attempt = 0; attempt < maxRetries; ++attempt) {
    if (attempt > 0) {
      Sleep(10 * attempt); // Small delay between retries
    }

    result = ExtractContents();
    if (!result.empty()) {
      // We got some content, return it
      break;
    }

    // Check if clipboard is still owned by someone (not empty)
    if (!IsClipboardFormatAvailable(CF_TEXT) &&
        !IsClipboardFormatAvailable(CF_UNICODETEXT) &&
        !IsClipboardFormatAvailable(CF_BITMAP)) {
      // Clipboard appears to be empty, no point in retrying
      break;
    }
  }

  return result;
}

flutter::EncodableList AdvancedClipboardPlugin::ExtractContents() {
  flutter::EncodableList results;

  if (!OpenClipboard(NULL)) return results;

  // Helper to add a part
  auto addPart = [&](const std::string& type, const std::vector<uint8_t>& raw,
                    const flutter::EncodableMap& metadata = {}) {
    flutter::EncodableMap map;
    map[flutter::EncodableValue("type")] = flutter::EncodableValue(type);
    map[flutter::EncodableValue("raw")] = flutter::EncodableValue(raw);
    if (!metadata.empty()) {
      map[flutter::EncodableValue("metadata")] = flutter::EncodableValue(metadata);
    }
    results.push_back(map);
  };

  // Check for bitmap and convert to PNG
  if (IsClipboardFormatAvailable(CF_BITMAP)) {
    HANDLE hBitmap = ::GetClipboardData(CF_BITMAP);
    if (hBitmap) {
      std::vector<uint8_t> pngData;
      if (HBITMAPToPNG((HBITMAP)hBitmap, pngData) && !pngData.empty()) {
        flutter::EncodableMap metadata;
        metadata[flutter::EncodableValue("format")] = flutter::EncodableValue("png");
        addPart("image", pngData, metadata);
      }
    }
  }

  // Check for text
  if (IsClipboardFormatAvailable(CF_UNICODETEXT)) {
    std::string text = GetClipboardText();
    if (!text.empty()) {
      // Check if it's a valid URL
      if (IsValidUrl(text)) {
        std::vector<uint8_t> text_data(text.begin(), text.end());
        addPart("url", text_data);
        addPart("text", text_data);
      } else {
        std::vector<uint8_t> text_data(text.begin(), text.end());
        addPart("text", text_data);
      }
    }
  }

  // Check for HTML
  if (CF_HTML && IsClipboardFormatAvailable(CF_HTML)) {
    auto html_data = this->GetClipboardData(CF_HTML);
    if (!html_data.empty()) {
      addPart("html", html_data);
    }
  }

  // Check for RTF
  if (CF_RTF && IsClipboardFormatAvailable(CF_RTF)) {
    auto rtf_data = this->GetClipboardData(CF_RTF);
    if (!rtf_data.empty()) {
      addPart("rtf", rtf_data);
    }
  }

  // Check for files
  if (IsClipboardFormatAvailable(CF_HDROP)) {
    HANDLE hDrop = ::GetClipboardData(CF_HDROP);
    if (hDrop) {
      HDROP hdrop = (HDROP)hDrop;
      UINT file_count = DragQueryFileW(hdrop, 0xFFFFFFFF, NULL, 0);

      for (UINT i = 0; i < file_count; ++i) {
        std::vector<WCHAR> filename(1024);
        UINT len = DragQueryFileW(hdrop, i, filename.data(), (UINT)filename.size());
        if (len > 0) {
          std::wstring wpath(filename.begin(), filename.begin() + len);
          std::string path = AdvancedClipboardPlugin::WideStringToUtf8(wpath);
          std::vector<uint8_t> path_data(path.begin(), path.end());

          flutter::EncodableMap metadata;
          DWORD attributes = GetFileAttributesA(path.c_str());
          metadata[flutter::EncodableValue("isDirectory")] =
              flutter::EncodableValue((attributes & FILE_ATTRIBUTE_DIRECTORY) != 0);

          addPart("fileUrl", path_data, metadata);
        }
      }
    }
  }

  CloseClipboard();
  return results;
}

bool AdvancedClipboardPlugin::WriteToClipboard(const std::vector<flutter::EncodableMap>& contents) {
  if (!OpenClipboard(NULL)) {
    return false;
  }

  if (!EmptyClipboard()) {
    CloseClipboard();
    return false;
  }

  ignore_next_change_ = true;

  if (contents.empty()) {
    CloseClipboard();
    return false;
  }

  int processed_count = 0;

  for (const auto& content : contents) {
    auto type_it = content.find(flutter::EncodableValue("type"));
    auto raw_it = content.find(flutter::EncodableValue("raw"));

    if (type_it == content.end() || raw_it == content.end()) continue;

    if (!std::holds_alternative<std::string>(type_it->second)) continue;
    std::string type = std::get<std::string>(type_it->second);

    std::vector<uint8_t> raw_data;
    if (std::holds_alternative<std::vector<uint8_t>>(raw_it->second)) {
      raw_data = std::get<std::vector<uint8_t>>(raw_it->second);
    } else {
      continue;
    }

    if (type == "text") {
      // raw_data contains UTF-8 encoded bytes
      std::string text(raw_data.begin(), raw_data.end());
      // Convert UTF-8 to UTF-16 wide string
      std::wstring wtext = Utf8ToWideString(text);

      // Allocate memory for the wide string including null terminator
      size_t bufferSize = (wtext.length() + 1) * sizeof(WCHAR);
      HGLOBAL hGlobal = GlobalAlloc(GMEM_MOVEABLE, bufferSize);
      if (hGlobal) {
        LPVOID pGlobal = GlobalLock(hGlobal);
        if (pGlobal) {
          memcpy(pGlobal, wtext.c_str(), bufferSize);
          GlobalUnlock(hGlobal);
          if (SetClipboardData(CF_UNICODETEXT, hGlobal) != NULL) {
            processed_count++;
          } else {
            // SetClipboardData failed, free the memory
            GlobalFree(hGlobal);
          }
        } else {
          GlobalFree(hGlobal);
        }
      }
    } else if (type == "html" && CF_HTML) {
      HGLOBAL hGlobal = GlobalAlloc(GMEM_MOVEABLE, raw_data.size());
      if (hGlobal) {
        LPVOID pGlobal = GlobalLock(hGlobal);
        if (pGlobal) {
          memcpy(pGlobal, raw_data.data(), raw_data.size());
          GlobalUnlock(hGlobal);
          if (SetClipboardData(CF_HTML, hGlobal) != NULL) {
            processed_count++;
          } else {
            GlobalFree(hGlobal);
          }
        } else {
          GlobalFree(hGlobal);
        }
      }
    } else if (type == "rtf" && CF_RTF) {
      HGLOBAL hGlobal = GlobalAlloc(GMEM_MOVEABLE, raw_data.size());
      if (hGlobal) {
        LPVOID pGlobal = GlobalLock(hGlobal);
        if (pGlobal) {
          memcpy(pGlobal, raw_data.data(), raw_data.size());
          GlobalUnlock(hGlobal);
          if (SetClipboardData(CF_RTF, hGlobal) != NULL) {
            processed_count++;
          } else {
            GlobalFree(hGlobal);
          }
        } else {
          GlobalFree(hGlobal);
        }
      }
    } else if (type == "url") {
      // raw_data contains UTF-8 encoded bytes
      std::string url(raw_data.begin(), raw_data.end());
      // Convert UTF-8 to UTF-16 wide string
      std::wstring wurl = Utf8ToWideString(url);

      HGLOBAL hGlobal = GlobalAlloc(GMEM_MOVEABLE, (wurl.size() + 1) * sizeof(WCHAR));
      if (hGlobal) {
        LPVOID pGlobal = GlobalLock(hGlobal);
        if (pGlobal) {
          memcpy(pGlobal, wurl.c_str(), (wurl.size() + 1) * sizeof(WCHAR));
          GlobalUnlock(hGlobal);
          if (SetClipboardData(CF_UNICODETEXT, hGlobal) != NULL) {
            processed_count++;
          } else {
            GlobalFree(hGlobal);
          }
        } else {
          GlobalFree(hGlobal);
        }
      }
    } else if (type == "fileUrl") {
      // raw_data contains UTF-8 encoded bytes
      std::string path(raw_data.begin(), raw_data.end());
      // Convert UTF-8 to UTF-16 wide string
      std::wstring wpath = Utf8ToWideString(path);

      HGLOBAL hGlobal = GlobalAlloc(GMEM_MOVEABLE, sizeof(DROPFILES) + (wpath.size() + 2) * sizeof(WCHAR));
      if (hGlobal) {
        DROPFILES* pDropFiles = (DROPFILES*)GlobalLock(hGlobal);
        if (pDropFiles) {
          pDropFiles->pFiles = sizeof(DROPFILES);
          pDropFiles->fWide = TRUE;

          WCHAR* pFiles = (WCHAR*)(pDropFiles + 1);
          wcscpy_s(pFiles, wpath.size() + 1, wpath.c_str());
          // Double null terminate for CF_HDROP format
          pFiles[wpath.size()] = L'\0';
          pFiles[wpath.size() + 1] = L'\0';

          GlobalUnlock(hGlobal);
          if (SetClipboardData(CF_HDROP, hGlobal) != NULL) {
            processed_count++;
          } else {
            GlobalFree(hGlobal);
          }
        } else {
          GlobalFree(hGlobal);
        }
      }
    } else if (type == "image") {
      // Convert PNG to HBITMAP and set to clipboard
      if (!raw_data.empty()) {
        HBITMAP hBitmap = nullptr;
        if (PNGToHBITMAP(raw_data.data(), raw_data.size(), hBitmap) && hBitmap) {
          // Get bitmap info for DIB creation
          BITMAP bm;
          if (GetObject(hBitmap, sizeof(BITMAP), &bm) > 0) {
            // Create DIB data from bitmap for better compatibility
            HDC hdc = GetDC(NULL);
            HDC memDC = CreateCompatibleDC(hdc);
            HBITMAP oldBmp = (HBITMAP)SelectObject(memDC, hBitmap);
            
            // Calculate DIB size
            int dibSize = sizeof(BITMAPINFOHEADER) + (bm.bmWidth * bm.bmHeight * 4);
            HGLOBAL hDib = GlobalAlloc(GMEM_MOVEABLE, dibSize);
            
            if (hDib) {
              BITMAPINFO* pBmi = (BITMAPINFO*)GlobalLock(hDib);
              if (pBmi) {
                // Fill BITMAPINFOHEADER
                pBmi->bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
                pBmi->bmiHeader.biWidth = bm.bmWidth;
                pBmi->bmiHeader.biHeight = bm.bmHeight;
                pBmi->bmiHeader.biPlanes = 1;
                pBmi->bmiHeader.biBitCount = 32;
                pBmi->bmiHeader.biCompression = BI_RGB;
                pBmi->bmiHeader.biSizeImage = bm.bmWidth * bm.bmHeight * 4;
                
                // Get bitmap bits
                uint8_t* pBits = (uint8_t*)(pBmi + 1);
                int lines = GetDIBits(memDC, hBitmap, 0, bm.bmHeight, pBits, pBmi, DIB_RGB_COLORS);
                
                if (lines > 0) {
                  GlobalUnlock(hDib);
                  
                  // Set both CF_BITMAP and CF_DIB for maximum compatibility
                  HANDLE result1 = SetClipboardData(CF_BITMAP, hBitmap);
                  HANDLE result2 = SetClipboardData(CF_DIB, hDib);
                  
                  if (result1 != NULL || result2 != NULL) {
                    // At least one format succeeded
                    processed_count++;
                    // If CF_BITMAP failed, we still own it
                    if (result1 == NULL) {
                      DeleteObject(hBitmap);
                    }
                    // If CF_DIB failed, we still own it
                    if (result2 == NULL) {
                      GlobalFree(hDib);
                    }
                  } else {
                    // Both failed, clean up
                    DeleteObject(hBitmap);
                    GlobalFree(hDib);
                  }
                } else {
                  // GetDIBits failed, unlock and free
                  GlobalUnlock(hDib);
                  GlobalFree(hDib);
                  // Fallback: only set CF_BITMAP
                  HANDLE result = SetClipboardData(CF_BITMAP, hBitmap);
                  if (result != NULL) {
                    processed_count++;
                  } else {
                    DeleteObject(hBitmap);
                  }
                }
              } else {
                GlobalFree(hDib);
                DeleteObject(hBitmap);
              }
            } else {
              // Fallback: only set CF_BITMAP if DIB allocation failed
              HANDLE result = SetClipboardData(CF_BITMAP, hBitmap);
              if (result != NULL) {
                processed_count++;
              } else {
                DeleteObject(hBitmap);
              }
            }
            
            SelectObject(memDC, oldBmp);
            DeleteDC(memDC);
            ReleaseDC(NULL, hdc);
          } else {
            // Fallback: only set CF_BITMAP if GetObject failed
            HANDLE result = SetClipboardData(CF_BITMAP, hBitmap);
            if (result != NULL) {
              processed_count++;
            } else {
              DeleteObject(hBitmap);
            }
          }
        }
      }
    }
  }

  CloseClipboard();
  
  // If we successfully wrote data, wait a bit then reset ignore flag
  if (processed_count > 0) {
    Sleep(20); // Short delay to allow clipboard to stabilize
    ignore_next_change_ = false; // Reset flag so change can be detected
  }
  
  // Return true only if at least one item was successfully processed
  return processed_count > 0;
}

// Utility methods
std::string AdvancedClipboardPlugin::WideStringToUtf8(const std::wstring& wstr) {
  if (wstr.empty()) return "";

  int size_needed = WideCharToMultiByte(CP_UTF8, 0, wstr.c_str(), static_cast<int>(wstr.size()),
                                        nullptr, 0, nullptr, nullptr);
  std::string result(size_needed, 0);
  WideCharToMultiByte(CP_UTF8, 0, wstr.c_str(), static_cast<int>(wstr.size()),
                      &result[0], size_needed, nullptr, nullptr);
  return result;
}

std::wstring AdvancedClipboardPlugin::Utf8ToWideString(const std::string& str) {
  if (str.empty()) return L"";

  int size_needed = MultiByteToWideChar(CP_UTF8, 0, str.c_str(), static_cast<int>(str.size()),
                                        nullptr, 0);
  std::wstring result(size_needed, 0);
  MultiByteToWideChar(CP_UTF8, 0, str.c_str(), static_cast<int>(str.size()),
                      &result[0], size_needed);
  return result;
}

std::string AdvancedClipboardPlugin::GetClipboardText() {
  HANDLE hData = ::GetClipboardData(CF_UNICODETEXT);
  if (!hData) return "";

  WCHAR* pText = (WCHAR*)GlobalLock(hData);
  if (!pText) return "";

  std::wstring wtext(pText);
  GlobalUnlock(hData);

  return AdvancedClipboardPlugin::WideStringToUtf8(wtext);
}

std::vector<uint8_t> AdvancedClipboardPlugin::GetClipboardData(UINT format) {
  std::vector<uint8_t> result;

  HANDLE hData = ::GetClipboardData(format);
  if (!hData) return result;

  SIZE_T size = GlobalSize(hData);
  if (size == 0) return result;

  LPVOID pData = GlobalLock(hData);
  if (!pData) return result;

  result.assign((uint8_t*)pData, (uint8_t*)pData + size);
  GlobalUnlock(hData);

  return result;
}

std::string AdvancedClipboardPlugin::GetProcessName(DWORD process_id) {
  std::wstring exePath = GetProcessExePath(process_id);
  if (exePath.empty()) return "";

  // Extract filename from path
  size_t pos = exePath.find_last_of(L"\\/");
  if (pos != std::wstring::npos) {
    exePath = exePath.substr(pos + 1);
  }

  return AdvancedClipboardPlugin::WideStringToUtf8(exePath);
}

std::wstring AdvancedClipboardPlugin::GetProcessExePath(DWORD process_id) {
  HANDLE hProcess = OpenProcess(PROCESS_QUERY_INFORMATION | PROCESS_VM_READ, FALSE, process_id);
  if (!hProcess) return L"";

  std::vector<WCHAR> buffer(MAX_PATH);
  DWORD size = static_cast<DWORD>(buffer.size());

  std::wstring result;
  if (QueryFullProcessImageNameW(hProcess, 0, buffer.data(), &size)) {
    result = std::wstring(buffer.data(), size);
  } else {
    // Fallback to GetModuleFileNameEx if QueryFullProcessImageName fails
    if (GetModuleFileNameExW(hProcess, nullptr, buffer.data(), static_cast<DWORD>(buffer.size()))) {
      result = std::wstring(buffer.data());
    }
  }

  CloseHandle(hProcess);
  return result;
}

std::string AdvancedClipboardPlugin::GetAppNameFromExe(const std::wstring& exePath) {
  if (exePath.empty()) return "";

  // Try to get app name from file version info
  DWORD dwSize = GetFileVersionInfoSizeW(exePath.c_str(), nullptr);
  if (dwSize > 0) {
    std::vector<BYTE> buffer(dwSize);
    if (GetFileVersionInfoW(exePath.c_str(), 0, dwSize, buffer.data())) {
      struct LANGANDCODEPAGE {
        WORD wLanguage;
        WORD wCodePage;
      } *lpTranslate;

      UINT cbTranslate = 0;
      if (VerQueryValueW(buffer.data(), L"\\VarFileInfo\\Translation",
                         reinterpret_cast<LPVOID*>(&lpTranslate), &cbTranslate) && cbTranslate > 0) {
        WCHAR subBlock[256];
        swprintf_s(subBlock, L"\\StringFileInfo\\%04x%04x\\FileDescription",
                   lpTranslate[0].wLanguage, lpTranslate[0].wCodePage);

        WCHAR* lpValue = nullptr;
        UINT cbValue = 0;
        if (VerQueryValueW(buffer.data(), subBlock, reinterpret_cast<LPVOID*>(&lpValue), &cbValue) && cbValue > 0) {
          std::wstring wname(lpValue);
          if (!wname.empty()) {
            return AdvancedClipboardPlugin::WideStringToUtf8(wname);
          }
        }

        // Try ProductName if FileDescription is empty
        swprintf_s(subBlock, L"\\StringFileInfo\\%04x%04x\\ProductName",
                   lpTranslate[0].wLanguage, lpTranslate[0].wCodePage);
        if (VerQueryValueW(buffer.data(), subBlock, reinterpret_cast<LPVOID*>(&lpValue), &cbValue) && cbValue > 0) {
          std::wstring wname(lpValue);
          if (!wname.empty()) {
            return AdvancedClipboardPlugin::WideStringToUtf8(wname);
          }
        }
      }
    }
  }

  // Fallback: use SHGetFileInfo to get file description
  SHFILEINFOW sfi = {};
  if (SHGetFileInfoW(exePath.c_str(), 0, &sfi, sizeof(sfi), SHGFI_DISPLAYNAME)) {
    std::wstring wname(sfi.szDisplayName);
    if (!wname.empty()) {
      return AdvancedClipboardPlugin::WideStringToUtf8(wname);
    }
  }

  // Last resort: extract filename without extension
  size_t pos = exePath.find_last_of(L"\\/");
  std::wstring filename = (pos != std::wstring::npos) ? exePath.substr(pos + 1) : exePath;
  pos = filename.find_last_of(L".");
  if (pos != std::wstring::npos) {
    filename = filename.substr(0, pos);
  }
  return AdvancedClipboardPlugin::WideStringToUtf8(filename);
}

HICON AdvancedClipboardPlugin::GetAppIcon(const std::wstring& exePath) {
  if (exePath.empty()) return nullptr;

  // Try ExtractIconEx first (extracts large icon)
  HICON hIconLarge = nullptr;
  HICON hIconSmall = nullptr;
  UINT iconCount = ExtractIconExW(exePath.c_str(), 0, &hIconLarge, &hIconSmall, 1);
  
  if (iconCount > 0 && hIconLarge) {
    if (hIconSmall) {
      DestroyIcon(hIconSmall);
    }
    return hIconLarge;
  }

  // Fallback: use SHGetFileInfo
  SHFILEINFOW sfi = {};
  if (SHGetFileInfoW(exePath.c_str(), 0, &sfi, sizeof(sfi), SHGFI_ICON | SHGFI_LARGEICON)) {
    return sfi.hIcon;
  }

  return nullptr;
}

bool AdvancedClipboardPlugin::IconToPNG(HICON hIcon, std::vector<uint8_t>& outPngBytes) {
  if (!hIcon) return false;

  // Get icon info
  ICONINFO iconInfo = {};
  if (!GetIconInfo(hIcon, &iconInfo)) {
    return false;
  }

  // Get bitmap dimensions
  BITMAP bm = {};
  if (iconInfo.hbmColor) {
    if (GetObject(iconInfo.hbmColor, sizeof(BITMAP), &bm) == 0) {
      if (iconInfo.hbmMask) DeleteObject(iconInfo.hbmMask);
      if (iconInfo.hbmColor) DeleteObject(iconInfo.hbmColor);
      return false;
    }
  } else if (iconInfo.hbmMask) {
    if (GetObject(iconInfo.hbmMask, sizeof(BITMAP), &bm) == 0) {
      if (iconInfo.hbmMask) DeleteObject(iconInfo.hbmMask);
      return false;
    }
    // For monochrome icons, height is doubled (mask + color)
    bm.bmHeight /= 2;
  } else {
    return false;
  }

  // Create a 32-bit ARGB bitmap using GDI+
  Gdiplus::Bitmap bitmap(bm.bmWidth, bm.bmHeight, PixelFormat32bppARGB);
  Gdiplus::Graphics graphics(&bitmap);
  
  // Clear with transparent background
  graphics.Clear(Gdiplus::Color(0, 0, 0, 0));
  
  // Get HDC from Graphics to draw icon
  HDC hdc = graphics.GetHDC();
  
  // Draw icon - DrawIconEx handles alpha channel properly when drawing to 32-bit ARGB surface
  DrawIconEx(hdc, 0, 0, hIcon, bm.bmWidth, bm.bmHeight, 0, nullptr, DI_NORMAL);
  
  graphics.ReleaseHDC(hdc);

  // For icons with separate mask (non-32-bit color bitmaps), manually apply mask for proper transparency
  if (iconInfo.hbmMask && iconInfo.hbmColor) {
    BITMAP colorBm = {};
    if (GetObject(iconInfo.hbmColor, sizeof(BITMAP), &colorBm) > 0) {
      // Only process if color bitmap is not 32-bit (doesn't have built-in alpha)
      if (colorBm.bmBitsPixel != 32) {
        // Lock bitmap bits to manually apply mask
        Gdiplus::BitmapData bitmapData;
        Gdiplus::Rect rect(0, 0, bm.bmWidth, bm.bmHeight);
        if (bitmap.LockBits(&rect, Gdiplus::ImageLockModeRead | Gdiplus::ImageLockModeWrite, PixelFormat32bppARGB, &bitmapData) == Gdiplus::Ok) {
          // Get mask bitmap data
          HDC maskDC = CreateCompatibleDC(nullptr);
          HBITMAP oldMaskBmp = (HBITMAP)SelectObject(maskDC, iconInfo.hbmMask);
          
          uint32_t* pixels = static_cast<uint32_t*>(bitmapData.Scan0);
          int stride = bitmapData.Stride / 4;
          
          // Apply mask: In icon masks, white (1) means transparent, black (0) means opaque
          // GetPixel returns COLORREF: RGB(255,255,255) for white, RGB(0,0,0) for black
          for (int y = 0; y < bm.bmHeight; ++y) {
            for (int x = 0; x < bm.bmWidth; ++x) {
              COLORREF maskColor = GetPixel(maskDC, x, y);
              // Check if mask pixel is white (transparent area)
              // For monochrome bitmaps, white is 0xFFFFFF
              if ((GetRValue(maskColor) > 127) && (GetGValue(maskColor) > 127) && (GetBValue(maskColor) > 127)) {
                // Mask is white: make pixel transparent
                pixels[y * stride + x] &= 0x00FFFFFF; // Clear alpha channel (set to 0)
              } else {
                // Mask is black: keep pixel opaque
                pixels[y * stride + x] |= 0xFF000000; // Set alpha to 255 (opaque)
              }
            }
          }
          
          SelectObject(maskDC, oldMaskBmp);
          DeleteDC(maskDC);
          bitmap.UnlockBits(&bitmapData);
        }
      }
    }
  }

  // Save to PNG
  CLSID pngClsid;
  if (GetEncoderClsid(L"image/png", &pngClsid)) {
    IStream* stream = nullptr;
    if (SUCCEEDED(CreateStreamOnHGlobal(nullptr, TRUE, &stream))) {
      if (bitmap.Save(stream, &pngClsid, nullptr) == Gdiplus::Ok) {
        STATSTG stat;
        stream->Stat(&stat, STATFLAG_NONAME);
        ULONG size = static_cast<ULONG>(stat.cbSize.QuadPart);
        outPngBytes.resize(size);

        LARGE_INTEGER zero = {};
        stream->Seek(zero, STREAM_SEEK_SET, nullptr);
        ULONG read = 0;
        stream->Read(outPngBytes.data(), size, &read);
        stream->Release();

        if (iconInfo.hbmMask) DeleteObject(iconInfo.hbmMask);
        if (iconInfo.hbmColor) DeleteObject(iconInfo.hbmColor);
        return read == size;
      }
      stream->Release();
    }
  }

  if (iconInfo.hbmMask) DeleteObject(iconInfo.hbmMask);
  if (iconInfo.hbmColor) DeleteObject(iconInfo.hbmColor);
  return false;
}

bool AdvancedClipboardPlugin::IsValidUrl(const std::string& text) {
  // Simple URL validation
  std::regex url_regex(R"(https?://[^\s]+)");
  return std::regex_match(text, url_regex);
}

flutter::EncodableMap AdvancedClipboardPlugin::SerializeAppInfo() {
  // Return cached app info (updated by WinEventProc when foreground window changes)
  return cached_app_info_;
}

bool AdvancedClipboardPlugin::HBITMAPToPNG(
    HBITMAP hBitmap,
    std::vector<uint8_t>& outPngBytes
) {
  if (!hBitmap) return false;

  Gdiplus::Bitmap bitmap(hBitmap, nullptr);

  CLSID pngClsid;
  if (!GetEncoderClsid(L"image/png", &pngClsid)) {
    return false;
  }

  IStream* stream = nullptr;
  if (FAILED(CreateStreamOnHGlobal(nullptr, TRUE, &stream))) {
    return false;
  }

  if (bitmap.Save(stream, &pngClsid, nullptr) != Gdiplus::Ok) {
    stream->Release();
    return false;
  }

  STATSTG stat;
  stream->Stat(&stat, STATFLAG_NONAME);
  ULONG size = static_cast<ULONG>(stat.cbSize.QuadPart);

  outPngBytes.resize(size);

  LARGE_INTEGER zero = {};
  stream->Seek(zero, STREAM_SEEK_SET, nullptr);

  ULONG read = 0;
  stream->Read(outPngBytes.data(), size, &read);

  stream->Release();
  return read == size;
}

bool AdvancedClipboardPlugin::PNGToHBITMAP(
    const uint8_t* pngData,
    size_t pngSize,
    HBITMAP& outBitmap
) {
  outBitmap = nullptr;
  if (!pngData || pngSize == 0) {
    return false;
  }

  // Create IStream
  IStream* stream = nullptr;
  HRESULT hr = CreateStreamOnHGlobal(nullptr, TRUE, &stream);
  if (FAILED(hr)) {
    return false;
  }

  ULONG written = 0;
  hr = stream->Write(pngData, static_cast<ULONG>(pngSize), &written);
  if (FAILED(hr)) {
    stream->Release();
    return false;
  }

  LARGE_INTEGER zero = {};
  zero.QuadPart = 0;
  hr = stream->Seek(zero, STREAM_SEEK_SET, nullptr);
  if (FAILED(hr)) {
    stream->Release();
    return false;
  }

  // Create Bitmap from stream
  Gdiplus::Bitmap* bitmap = Gdiplus::Bitmap::FromStream(stream);
  stream->Release();

  if (!bitmap) {
    return false;
  }

  Gdiplus::Status status = bitmap->GetLastStatus();
  if (status != Gdiplus::Ok) {
    delete bitmap;
    return false;
  }

  // Use GDI+ GetHBITMAP to create a screen-compatible bitmap
  // This is the most reliable method for clipboard operations
  Gdiplus::Color transparent(0, 0, 0, 0);
  status = bitmap->GetHBITMAP(transparent, &outBitmap);
  
  delete bitmap;
  
  return (status == Gdiplus::Ok && outBitmap != nullptr);
}

bool AdvancedClipboardPlugin::GetEncoderClsid(const WCHAR* format, CLSID* pClsid) {
  UINT num = 0;           // number of image encoders
  UINT size = 0;          // size of the image encoder array in bytes

  Gdiplus::ImageCodecInfo* pImageCodecInfo = nullptr;

  Gdiplus::GetImageEncodersSize(&num, &size);
  if (size == 0)
    return false;  // Failure

  pImageCodecInfo = (Gdiplus::ImageCodecInfo*)(malloc(size));
  if (pImageCodecInfo == nullptr)
    return false;  // Failure

  Gdiplus::GetImageEncoders(num, size, pImageCodecInfo);

  for (UINT j = 0; j < num; ++j) {
    if (wcscmp(pImageCodecInfo[j].MimeType, format) == 0) {
      *pClsid = pImageCodecInfo[j].Clsid;
      free(pImageCodecInfo);
      return true;  // Success
    }
  }

  free(pImageCodecInfo);
  return false;  // Failure
}

}  // namespace advanced_clipboard
