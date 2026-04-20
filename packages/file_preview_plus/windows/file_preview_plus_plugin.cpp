#include "file_preview_plus_plugin.h"

// This must be included before many other Windows headers.
#include <windows.h>

// For getPlatformVersion; remove unless needed for your plugin implementation.
#include <VersionHelpers.h>

#include <ShObjIdl.h>
#include <Shlwapi.h>
#include <Shellapi.h>
#include <wincodec.h>

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <filesystem>
#include <chrono>
#include <memory>
#include <optional>
#include <sstream>
#include <string>
#include <vector>

namespace file_preview_plus {

namespace {

using EncodableMap = std::map<flutter::EncodableValue, flutter::EncodableValue>;

std::optional<std::string> GetStringArg(const flutter::EncodableValue* args,
                                       const char* key) {
  if (!args || !std::holds_alternative<EncodableMap>(*args)) return std::nullopt;
  const auto& map = std::get<EncodableMap>(*args);
  auto it = map.find(flutter::EncodableValue(key));
  if (it == map.end()) return std::nullopt;
  if (std::holds_alternative<std::string>(it->second)) {
    return std::get<std::string>(it->second);
  }
  return std::nullopt;
}

int GetIntArg(const flutter::EncodableValue* args, const char* key, int def) {
  if (!args || !std::holds_alternative<EncodableMap>(*args)) return def;
  const auto& map = std::get<EncodableMap>(*args);
  auto it = map.find(flutter::EncodableValue(key));
  if (it == map.end()) return def;
  if (std::holds_alternative<int>(it->second)) return std::get<int>(it->second);
  if (std::holds_alternative<int64_t>(it->second))
    return static_cast<int>(std::get<int64_t>(it->second));
  return def;
}

std::wstring Utf8ToWide(const std::string& s) {
  if (s.empty()) return L"";
  int len = MultiByteToWideChar(CP_UTF8, 0, s.c_str(), -1, nullptr, 0);
  std::wstring out(len - 1, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, s.c_str(), -1, out.data(), len);
  return out;
}

std::string WideToUtf8(const std::wstring& s) {
  if (s.empty()) return "";
  int len = WideCharToMultiByte(CP_UTF8, 0, s.c_str(), -1, nullptr, 0, nullptr, nullptr);
  std::string out(len - 1, '\0');
  WideCharToMultiByte(CP_UTF8, 0, s.c_str(), -1, out.data(), len, nullptr, nullptr);
  return out;
}

std::optional<std::string> QueryMimeTypeFromExtension(const std::wstring& path) {
  std::wstring ext = std::filesystem::path(path).extension().wstring();
  if (ext.empty()) return std::nullopt;
  wchar_t content_type[256];
  DWORD content_type_len = static_cast<DWORD>(std::size(content_type));
  HRESULT hr = AssocQueryStringW(0, ASSOCSTR_CONTENTTYPE, ext.c_str(), nullptr,
                                content_type, &content_type_len);
  if (SUCCEEDED(hr) && content_type[0] != L'\0') {
    return WideToUtf8(content_type);
  }
  return std::nullopt;
}

std::optional<std::vector<uint8_t>> PngBytesFromHBitmap(HBITMAP hbitmap) {
  if (!hbitmap) return std::nullopt;
  HRESULT hr = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  const bool did_init = SUCCEEDED(hr);

  IWICImagingFactory* factory = nullptr;
  hr = CoCreateInstance(CLSID_WICImagingFactory, nullptr, CLSCTX_INPROC_SERVER,
                        IID_PPV_ARGS(&factory));
  if (FAILED(hr) || !factory) {
    if (did_init) CoUninitialize();
    return std::nullopt;
  }

  IWICBitmap* wic_bitmap = nullptr;
  hr = factory->CreateBitmapFromHBITMAP(hbitmap, nullptr, WICBitmapUseAlpha, &wic_bitmap);
  if (FAILED(hr) || !wic_bitmap) {
    factory->Release();
    if (did_init) CoUninitialize();
    return std::nullopt;
  }

  IStream* stream = nullptr;
  hr = CreateStreamOnHGlobal(nullptr, TRUE, &stream);
  if (FAILED(hr) || !stream) {
    wic_bitmap->Release();
    factory->Release();
    if (did_init) CoUninitialize();
    return std::nullopt;
  }

  IWICBitmapEncoder* encoder = nullptr;
  hr = factory->CreateEncoder(GUID_ContainerFormatPng, nullptr, &encoder);
  if (FAILED(hr) || !encoder) {
    stream->Release();
    wic_bitmap->Release();
    factory->Release();
    if (did_init) CoUninitialize();
    return std::nullopt;
  }

  hr = encoder->Initialize(stream, WICBitmapEncoderNoCache);
  IWICBitmapFrameEncode* frame = nullptr;
  if (SUCCEEDED(hr)) hr = encoder->CreateNewFrame(&frame, nullptr);
  if (SUCCEEDED(hr)) hr = frame->Initialize(nullptr);
  if (SUCCEEDED(hr)) hr = frame->WriteSource(wic_bitmap, nullptr);
  if (SUCCEEDED(hr)) hr = frame->Commit();
  if (SUCCEEDED(hr)) hr = encoder->Commit();

  std::optional<std::vector<uint8_t>> out = std::nullopt;
  if (SUCCEEDED(hr)) {
    HGLOBAL hglobal = nullptr;
    if (SUCCEEDED(GetHGlobalFromStream(stream, &hglobal)) && hglobal) {
      SIZE_T sz = GlobalSize(hglobal);
      void* ptr = GlobalLock(hglobal);
      if (ptr && sz > 0) {
        std::vector<uint8_t> bytes(sz);
        memcpy(bytes.data(), ptr, sz);
        out = std::move(bytes);
      }
      if (ptr) GlobalUnlock(hglobal);
    }
  }

  if (frame) frame->Release();
  encoder->Release();
  stream->Release();
  wic_bitmap->Release();
  factory->Release();
  if (did_init) CoUninitialize();
  return out;
}

HBITMAP HBitmapFromHIcon(HICON icon, int width, int height) {
  if (!icon) return nullptr;
  BITMAPINFO bmi = {};
  bmi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  bmi.bmiHeader.biWidth = width;
  bmi.bmiHeader.biHeight = -height;  // top-down
  bmi.bmiHeader.biPlanes = 1;
  bmi.bmiHeader.biBitCount = 32;
  bmi.bmiHeader.biCompression = BI_RGB;

  void* bits = nullptr;
  HDC hdc = GetDC(nullptr);
  HBITMAP dib = CreateDIBSection(hdc, &bmi, DIB_RGB_COLORS, &bits, nullptr, 0);
  ReleaseDC(nullptr, hdc);
  if (!dib) return nullptr;

  HDC memdc = CreateCompatibleDC(nullptr);
  HGDIOBJ old = SelectObject(memdc, dib);
  RECT rc{0, 0, width, height};
  HBRUSH brush = CreateSolidBrush(RGB(0, 0, 0));
  FillRect(memdc, &rc, brush);
  DeleteObject(brush);
  DrawIconEx(memdc, 0, 0, icon, width, height, 0, nullptr, DI_NORMAL);
  SelectObject(memdc, old);
  DeleteDC(memdc);
  return dib;
}

std::optional<std::vector<uint8_t>> GetThumbnailPngForPath(const std::wstring& path,
                                                           int width, int height) {
  HRESULT hr = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  const bool did_init = SUCCEEDED(hr);

  IShellItem* item = nullptr;
  hr = SHCreateItemFromParsingName(path.c_str(), nullptr, IID_PPV_ARGS(&item));
  if (SUCCEEDED(hr) && item) {
    IShellItemImageFactory* factory = nullptr;
    hr = item->QueryInterface(IID_PPV_ARGS(&factory));
    if (SUCCEEDED(hr) && factory) {
      SIZE size{width, height};
      HBITMAP hbitmap = nullptr;
      hr = factory->GetImage(size, SIIGBF_BIGGERSIZEOK, &hbitmap);
      factory->Release();
      item->Release();
      if (SUCCEEDED(hr) && hbitmap) {
        auto png = PngBytesFromHBitmap(hbitmap);
        DeleteObject(hbitmap);
        if (did_init) CoUninitialize();
        if (png) return png;
      }
    } else {
      item->Release();
    }
  }

  // Fallback: system icon via SHGetFileInfo.
  SHFILEINFOW sfi = {};
  if (SHGetFileInfoW(path.c_str(), 0, &sfi, sizeof(sfi), SHGFI_ICON | SHGFI_LARGEICON)) {
    HICON icon = sfi.hIcon;
    HBITMAP dib = HBitmapFromHIcon(icon, width, height);
    DestroyIcon(icon);
    if (dib) {
      auto png = PngBytesFromHBitmap(dib);
      DeleteObject(dib);
      if (did_init) CoUninitialize();
      if (png) return png;
    }
  }

  if (did_init) CoUninitialize();
  return std::nullopt;
}

}  // namespace

// static
void FilePreviewPlusPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows *registrar) {
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), "file_preview_plus",
          &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<FilePreviewPlusPlugin>();

  channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto &call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });

  registrar->AddPlugin(std::move(plugin));
}

FilePreviewPlusPlugin::FilePreviewPlusPlugin() {}

FilePreviewPlusPlugin::~FilePreviewPlusPlugin() {}

void FilePreviewPlusPlugin::HandleMethodCall(
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
  } else if (method_call.method_name().compare("getFileInfo") == 0) {
    auto path_opt = GetStringArg(method_call.arguments(), "path");
    if (!path_opt || path_opt->empty()) {
      result->Error("invalid_args", "Missing path");
      return;
    }
    const std::wstring wpath = Utf8ToWide(*path_opt);
    std::error_code ec;
    auto p = std::filesystem::path(wpath);

    EncodableMap map;
    map[flutter::EncodableValue("path")] = flutter::EncodableValue(*path_opt);
    map[flutter::EncodableValue("name")] = flutter::EncodableValue(WideToUtf8(p.filename().wstring()));
    map[flutter::EncodableValue("isDirectory")] =
        flutter::EncodableValue(std::filesystem::is_directory(p, ec));

    if (!ec && std::filesystem::exists(p, ec) && !std::filesystem::is_directory(p, ec)) {
      auto sz = std::filesystem::file_size(p, ec);
      if (!ec) map[flutter::EncodableValue("size")] = flutter::EncodableValue(static_cast<int64_t>(sz));
    }

    // Best-effort modified time.
    if (!ec && std::filesystem::exists(p, ec)) {
      auto ft = std::filesystem::last_write_time(p, ec);
      if (!ec) {
        // Convert to Unix ms.
        auto sctp = std::chrono::time_point_cast<std::chrono::milliseconds>(
            ft - decltype(ft)::clock::now() + std::chrono::system_clock::now());
        auto ms = sctp.time_since_epoch().count();
        map[flutter::EncodableValue("modifiedMs")] = flutter::EncodableValue(static_cast<int64_t>(ms));
      }
    }

    if (auto mime = QueryMimeTypeFromExtension(wpath)) {
      map[flutter::EncodableValue("mimeType")] = flutter::EncodableValue(*mime);
    }

    result->Success(flutter::EncodableValue(map));
  } else if (method_call.method_name().compare("getThumbnail") == 0) {
    auto path_opt = GetStringArg(method_call.arguments(), "path");
    if (!path_opt || path_opt->empty()) {
      result->Error("invalid_args", "Missing path");
      return;
    }
    int width = std::max(1, GetIntArg(method_call.arguments(), "width", 256));
    int height = std::max(1, GetIntArg(method_call.arguments(), "height", 256));
    auto png = GetThumbnailPngForPath(Utf8ToWide(*path_opt), width, height);
    if (!png) {
      result->Success(flutter::EncodableValue());
      return;
    }
    result->Success(flutter::EncodableValue(*png));
  } else {
    result->NotImplemented();
  }
}

}  // namespace file_preview_plus
