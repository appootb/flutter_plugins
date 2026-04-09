#ifndef FLUTTER_PLUGIN_ADVANCED_CLIPBOARD_PLUGIN_H_
#define FLUTTER_PLUGIN_ADVANCED_CLIPBOARD_PLUGIN_H_

#include <flutter/event_channel.h>
#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <memory>
#include <string>
#include <vector>
#include <windows.h>
#include <gdiplus.h>

namespace advanced_clipboard {

class AdvancedClipboardPlugin : public flutter::Plugin {
 private:
  // Static instance pointer for WinEventProc callback
  static AdvancedClipboardPlugin* instance_;

 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  AdvancedClipboardPlugin();

  virtual ~AdvancedClipboardPlugin();

  // Disallow copy and assign.
  AdvancedClipboardPlugin(const AdvancedClipboardPlugin&) = delete;
  AdvancedClipboardPlugin& operator=(const AdvancedClipboardPlugin&) = delete;

  // Called when a method is called on this plugin's channel from Dart.
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);


 private:
  // Channels
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> method_channel_;
  std::unique_ptr<flutter::EventChannel<flutter::EncodableValue>> event_channel_;
  std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> event_sink_;

  // Clipboard monitoring
  HWND hwnd_;
  bool is_listening_ = false;
  DWORD last_clipboard_sequence_ = 0;
  bool ignore_next_change_ = false;

  // Window event hook for foreground window tracking
  HWINEVENTHOOK win_event_hook_ = nullptr;
  flutter::EncodableMap cached_app_info_;

  // GDI+ for image processing
  ULONG_PTR gdiplus_token_;

  // Window procedure for clipboard notifications
  static LRESULT CALLBACK WndProc(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam);
  LRESULT HandleWindowMessage(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam);

  // Monitoring methods
  void StartMonitoring();
  void StopMonitoring();
  void CheckClipboardChange();

  // Clipboard operations
  flutter::EncodableMap CreateClipboardEntry(DWORD sequence_number);
  flutter::EncodableList ExtractContents();
  flutter::EncodableList ExtractContentsWithRetry();
  bool WriteToClipboard(const std::vector<flutter::EncodableMap>& contents);

  // Utility methods
  static std::string WideStringToUtf8(const std::wstring& wstr);
  static std::wstring Utf8ToWideString(const std::string& str);
  std::string GetClipboardText();
  std::vector<uint8_t> GetClipboardData(UINT format);
  std::string GetProcessName(DWORD process_id);
  std::wstring GetProcessExePath(DWORD process_id);
  std::string GetAppNameFromExe(const std::wstring& exePath);
  HICON GetAppIcon(const std::wstring& exePath);
  bool IconToPNG(HICON hIcon, std::vector<uint8_t>& outPngBytes);
  bool IsValidUrl(const std::string& text);
  flutter::EncodableMap SerializeAppInfo();
  void UpdateCachedAppInfo(HWND hwnd);
  static bool IsValidUserAppWindow(HWND hwnd);
  static bool IsScreenshotTool(HWND hwnd, const std::string& processName);
  static bool IsWindowFullscreen(HWND hwnd);
  static bool IsWindowBorderlessOrLayered(HWND hwnd);
  static bool IsWindowTransparent(HWND hwnd);
  static void CALLBACK WinEventProc(HWINEVENTHOOK hWinEventHook, DWORD event, HWND hwnd, LONG idObject, LONG idChild, DWORD dwEventThread, DWORD dwmsTimeStamp);
  bool HBITMAPToPNG(HBITMAP hBitmap, std::vector<uint8_t>& outPngBytes);
  bool PNGToHBITMAP(const uint8_t* pngData, size_t pngSize, HBITMAP& outBitmap);
  static bool GetEncoderClsid(const WCHAR* format, CLSID* pClsid);

  // Clipboard format constants
  static const UINT CF_HTML;
  static const UINT CF_RTF;
};

}  // namespace advanced_clipboard

#endif  // FLUTTER_PLUGIN_ADVANCED_CLIPBOARD_PLUGIN_H_
