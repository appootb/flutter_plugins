#include "native_ocr_plugin.h"

// This must be included before many other Windows headers.
#include <windows.h>

// For getPlatformVersion; remove unless needed for your plugin implementation.
#include <VersionHelpers.h>

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Globalization.h>
#include <winrt/Windows.Graphics.Imaging.h>
#include <winrt/Windows.Media.Ocr.h>
#include <winrt/Windows.Storage.h>
#include <winrt/Windows.Storage.Streams.h>

#include <memory>
#include <sstream>
#include <string>
#include <thread>
#include <vector>

namespace native_ocr {

namespace {

void EnsureWinRtApartmentOnCurrentThread() {
  thread_local bool initialized = false;
  if (!initialized) {
    winrt::init_apartment(winrt::apartment_type::multi_threaded);
    initialized = true;
  }
}

std::wstring Utf8ToWide(const std::string& s) {
  if (s.empty()) return std::wstring();
  int size_needed = MultiByteToWideChar(CP_UTF8, 0, s.c_str(),
                                       static_cast<int>(s.size()), NULL, 0);
  std::wstring w(size_needed, 0);
  MultiByteToWideChar(CP_UTF8, 0, s.c_str(), static_cast<int>(s.size()),
                      &w[0], size_needed);
  return w;
}

std::string WideToUtf8(const std::wstring& w) {
  if (w.empty()) return std::string();
  int size_needed = WideCharToMultiByte(CP_UTF8, 0, w.c_str(),
                                       static_cast<int>(w.size()), NULL, 0,
                                       NULL, NULL);
  std::string s(size_needed, 0);
  WideCharToMultiByte(CP_UTF8, 0, w.c_str(), static_cast<int>(w.size()),
                      &s[0], size_needed, NULL, NULL);
  return s;
}

bool IsCjk(wchar_t ch) {
  // Basic heuristic covering common CJK ranges.
  return (ch >= 0x4E00 && ch <= 0x9FFF) ||  // CJK Unified Ideographs
         (ch >= 0x3400 && ch <= 0x4DBF) ||  // Extension A
         (ch >= 0x3040 && ch <= 0x30FF) ||  // Hiragana/Katakana
         (ch >= 0xAC00 && ch <= 0xD7AF);    // Hangul
}

std::wstring RemoveSpacesBetweenCjk(const std::wstring& input) {
  if (input.size() < 3) return input;
  std::wstring out;
  out.reserve(input.size());
  for (size_t i = 0; i < input.size(); ++i) {
    if (input[i] == L' ' && i > 0 && i + 1 < input.size() &&
        IsCjk(input[i - 1]) && IsCjk(input[i + 1])) {
      continue;
    }
    out.push_back(input[i]);
  }
  return out;
}

winrt::Windows::Graphics::Imaging::SoftwareBitmap ConvertToBgra8Premultiplied(
    winrt::Windows::Graphics::Imaging::SoftwareBitmap bitmap) {
  using namespace winrt::Windows::Graphics::Imaging;
  if (bitmap.BitmapPixelFormat() == BitmapPixelFormat::Bgra8 &&
      bitmap.BitmapAlphaMode() == BitmapAlphaMode::Premultiplied) {
    return bitmap;
  }
  return SoftwareBitmap::Convert(bitmap, BitmapPixelFormat::Bgra8,
                                 BitmapAlphaMode::Premultiplied);
}

winrt::Windows::Media::Ocr::OcrEngine CreateEngineFromLanguageCodes(
    const flutter::EncodableMap* args_map) {
  using namespace winrt::Windows::Media::Ocr;
  using namespace winrt::Windows::Globalization;

  if (args_map) {
    auto it = args_map->find(flutter::EncodableValue("languageCodes"));
    if (it != args_map->end()) {
      if (auto list = std::get_if<flutter::EncodableList>(&it->second)) {
        for (const auto& v : *list) {
          if (auto s = std::get_if<std::string>(&v)) {
            try {
              auto engine =
                  OcrEngine::TryCreateFromLanguage(Language(Utf8ToWide(*s)));
              if (engine) return engine;
            } catch (...) {
              // Try next language.
            }
          }
        }
      }
    }
  }

  auto from_profile = OcrEngine::TryCreateFromUserProfileLanguages();
  if (from_profile) return from_profile;

  auto available = OcrEngine::AvailableRecognizerLanguages();
  if (available.Size() > 0) {
    auto engine = OcrEngine::TryCreateFromLanguage(available.GetAt(0));
    if (engine) return engine;
  }

  return nullptr;
}

winrt::Windows::Graphics::Imaging::SoftwareBitmap LoadBitmapFromPath(
    const std::string& path_utf8) {
  using namespace winrt::Windows::Storage;
  using namespace winrt::Windows::Storage::Streams;
  using namespace winrt::Windows::Graphics::Imaging;

  auto file = StorageFile::GetFileFromPathAsync(Utf8ToWide(path_utf8)).get();
  auto stream = file.OpenAsync(FileAccessMode::Read).get();
  auto decoder = BitmapDecoder::CreateAsync(stream).get();
  auto bitmap = decoder.GetSoftwareBitmapAsync().get();
  return ConvertToBgra8Premultiplied(bitmap);
}

winrt::Windows::Graphics::Imaging::SoftwareBitmap LoadBitmapFromBytes(
    const std::vector<uint8_t>& bytes) {
  using namespace winrt::Windows::Storage::Streams;
  using namespace winrt::Windows::Graphics::Imaging;

  InMemoryRandomAccessStream stream;
  DataWriter writer(stream);
  writer.WriteBytes(winrt::array_view<const uint8_t>(bytes));
  writer.StoreAsync().get();
  writer.FlushAsync().get();
  writer.DetachStream();

  stream.Seek(0);
  auto decoder = BitmapDecoder::CreateAsync(stream).get();
  auto bitmap = decoder.GetSoftwareBitmapAsync().get();
  return ConvertToBgra8Premultiplied(bitmap);
}

bool ReadStringArg(const flutter::EncodableMap& map, const char* key,
                   std::string* out) {
  auto it = map.find(flutter::EncodableValue(key));
  if (it == map.end()) return false;
  if (auto s = std::get_if<std::string>(&it->second)) {
    *out = *s;
    return true;
  }
  return false;
}

bool ReadBytesArg(const flutter::EncodableMap& map, const char* key,
                  std::vector<uint8_t>* out) {
  auto it = map.find(flutter::EncodableValue(key));
  if (it == map.end()) return false;
  if (auto l = std::get_if<std::vector<uint8_t>>(&it->second)) {
    *out = *l;
    return true;
  }
  return false;
}

}  // namespace

// static
void NativeOcrPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows *registrar) {
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), "native_ocr",
          &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<NativeOcrPlugin>();

  channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto &call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });

  registrar->AddPlugin(std::move(plugin));
}

NativeOcrPlugin::NativeOcrPlugin() {}

NativeOcrPlugin::~NativeOcrPlugin() {}

void NativeOcrPlugin::HandleMethodCall(
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
  } else if (method_call.method_name().compare("recognizeText") == 0) {
    const auto* args_map =
        std::get_if<flutter::EncodableMap>(method_call.arguments());
    if (!args_map) {
      result->Error("INVALID_ARGUMENT", "Missing or invalid arguments map.");
      return;
    }

    std::string path;
    if (!ReadStringArg(*args_map, "imagePath", &path) || path.empty()) {
      result->Error("INVALID_ARGUMENT", "Missing or invalid 'imagePath'.");
      return;
    }

    try {
      std::string out_text;
      std::thread worker([&]() {
        EnsureWinRtApartmentOnCurrentThread();
        auto bitmap = LoadBitmapFromPath(path);
        auto engine = CreateEngineFromLanguageCodes(args_map);
        if (!engine) {
          throw std::runtime_error("No OCR engine available.");
        }
        auto ocr = engine.RecognizeAsync(bitmap).get();
        auto text = ocr.Text();
        out_text = WideToUtf8(RemoveSpacesBetweenCjk(text.c_str()));
      });
      worker.join();
      result->Success(flutter::EncodableValue(out_text));
    } catch (const std::exception& e) {
      result->Error("OCR_ERROR", "Windows OCR failed.", e.what());
    } catch (...) {
      result->Error("OCR_ERROR", "Windows OCR failed.");
    }
  } else if (method_call.method_name().compare("recognizeTextFromBytes") == 0) {
    const auto* args_map =
        std::get_if<flutter::EncodableMap>(method_call.arguments());
    if (!args_map) {
      result->Error("INVALID_ARGUMENT", "Missing or invalid arguments map.");
      return;
    }

    std::vector<uint8_t> bytes;
    if (!ReadBytesArg(*args_map, "imageBytes", &bytes) || bytes.empty()) {
      result->Error("INVALID_ARGUMENT", "Missing or invalid 'imageBytes'.");
      return;
    }

    try {
      std::string out_text;
      std::thread worker([&]() {
        EnsureWinRtApartmentOnCurrentThread();
        auto bitmap = LoadBitmapFromBytes(bytes);
        auto engine = CreateEngineFromLanguageCodes(args_map);
        if (!engine) {
          throw std::runtime_error("No OCR engine available.");
        }
        auto ocr = engine.RecognizeAsync(bitmap).get();
        auto text = ocr.Text();
        out_text = WideToUtf8(RemoveSpacesBetweenCjk(text.c_str()));
      });
      worker.join();
      result->Success(flutter::EncodableValue(out_text));
    } catch (const std::exception& e) {
      result->Error("OCR_ERROR", "Windows OCR failed.", e.what());
    } catch (...) {
      result->Error("OCR_ERROR", "Windows OCR failed.");
    }
  } else {
    result->NotImplemented();
  }
}

}  // namespace native_ocr
