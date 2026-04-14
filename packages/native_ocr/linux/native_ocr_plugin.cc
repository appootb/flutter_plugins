#include "include/native_ocr/native_ocr_plugin.h"

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>
#include <sys/utsname.h>

#include <cstring>
#include <string>
#include <vector>

#include "native_ocr_plugin_private.h"

#if HAS_TESSERACT
#include <leptonica/allheaders.h>
#include <tesseract/baseapi.h>
#endif

#define NATIVE_OCR_PLUGIN(obj) \
  (G_TYPE_CHECK_INSTANCE_CAST((obj), native_ocr_plugin_get_type(), \
                              NativeOcrPlugin))

struct _NativeOcrPlugin {
  GObject parent_instance;
};

G_DEFINE_TYPE(NativeOcrPlugin, native_ocr_plugin, g_object_get_type())

// Called when a method call is received from Flutter.
static void native_ocr_plugin_handle_method_call(
    NativeOcrPlugin* self,
    FlMethodCall* method_call) {
  g_autoptr(FlMethodResponse) response = nullptr;

  const gchar* method = fl_method_call_get_name(method_call);

  if (strcmp(method, "getPlatformVersion") == 0) {
    response = get_platform_version();
  } else if (strcmp(method, "recognizeText") == 0) {
    response = recognize_text(fl_method_call_get_args(method_call));
  } else if (strcmp(method, "recognizeTextFromBytes") == 0) {
    response = recognize_text_from_bytes(fl_method_call_get_args(method_call));
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }

  fl_method_call_respond(method_call, response, nullptr);
}

FlMethodResponse* get_platform_version() {
  struct utsname uname_data = {};
  uname(&uname_data);
  g_autofree gchar *version = g_strdup_printf("Linux %s", uname_data.version);
  g_autoptr(FlValue) result = fl_value_new_string(version);
  return FL_METHOD_RESPONSE(fl_method_success_response_new(result));
}

#if HAS_TESSERACT
static std::string NormalizeLang(const std::string& bcp47) {
  // Very small mapping set; extend as needed.
  auto lower = bcp47;
  for (auto& c : lower) c = static_cast<char>(g_ascii_tolower(c));
  if (g_str_has_prefix(lower.c_str(), "zh-hans")) return "chi_sim";
  if (g_str_has_prefix(lower.c_str(), "zh-hant")) return "chi_tra";
  if (g_str_has_prefix(lower.c_str(), "en")) return "eng";
  if (g_str_has_prefix(lower.c_str(), "ja")) return "jpn";
  if (g_str_has_prefix(lower.c_str(), "ko")) return "kor";
  return "eng";
}

static std::string BuildTessLang(FlValue* args) {
  if (!args || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) return "eng";
  FlValue* v = fl_value_lookup_string(args, "languageCodes");
  if (!v || fl_value_get_type(v) != FL_VALUE_TYPE_LIST) return "eng";
  const size_t n = fl_value_get_length(v);
  if (n == 0) return "eng";
  std::vector<std::string> langs;
  langs.reserve(n);
  for (size_t i = 0; i < n; ++i) {
    FlValue* item = fl_value_get_list_value(v, i);
    if (!item || fl_value_get_type(item) != FL_VALUE_TYPE_STRING) continue;
    langs.push_back(NormalizeLang(fl_value_get_string(item)));
  }
  if (langs.empty()) return "eng";
  // De-dup, keep order.
  std::vector<std::string> uniq;
  for (const auto& l : langs) {
    bool seen = false;
    for (const auto& u : uniq) {
      if (u == l) {
        seen = true;
        break;
      }
    }
    if (!seen) uniq.push_back(l);
  }
  std::string joined;
  for (size_t i = 0; i < uniq.size(); ++i) {
    if (i) joined += "+";
    joined += uniq[i];
  }
  return joined;
}

static FlMethodResponse* TessOcrPix(Pix* pix, const std::string& lang) {
  if (!pix) {
    return FL_METHOD_RESPONSE(fl_method_error_response_new(
        "INVALID_IMAGE", "Failed to decode image.", nullptr));
  }

  tesseract::TessBaseAPI api;
  if (api.Init(nullptr, lang.c_str(), tesseract::OEM_DEFAULT) != 0) {
    pixDestroy(&pix);
    return FL_METHOD_RESPONSE(fl_method_error_response_new(
        "OCR_ERROR", "Failed to initialize Tesseract.", lang.c_str()));
  }
  api.SetImage(pix);
  char* text = api.GetUTF8Text();
  pixDestroy(&pix);
  if (!text) {
    return FL_METHOD_RESPONSE(fl_method_success_response_new(
        fl_value_new_string("")));
  }
  g_autofree gchar* gtext = g_strdup(text);
  delete[] text;
  g_autoptr(FlValue) result = fl_value_new_string(gtext);
  return FL_METHOD_RESPONSE(fl_method_success_response_new(result));
}
#endif

FlMethodResponse* recognize_text(FlValue* args) {
  if (!args || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
    return FL_METHOD_RESPONSE(fl_method_error_response_new(
        "INVALID_ARGUMENT", "Missing or invalid arguments map.", nullptr));
  }

  FlValue* path_v = fl_value_lookup_string(args, "imagePath");
  if (!path_v || fl_value_get_type(path_v) != FL_VALUE_TYPE_STRING) {
    return FL_METHOD_RESPONSE(fl_method_error_response_new(
        "INVALID_ARGUMENT", "Missing or invalid 'imagePath'.", nullptr));
  }
  const gchar* path = fl_value_get_string(path_v);
  if (!path || strlen(path) == 0) {
    return FL_METHOD_RESPONSE(fl_method_error_response_new(
        "INVALID_ARGUMENT", "Missing or invalid 'imagePath'.", nullptr));
  }

#if HAS_TESSERACT
  const std::string lang = BuildTessLang(args);
  Pix* pix = pixRead(path);
  return TessOcrPix(pix, lang);
#else
  return FL_METHOD_RESPONSE(fl_method_error_response_new(
      "UNAVAILABLE",
      "Tesseract/Leptonica not found. Install libtesseract-dev and libleptonica-dev then rebuild.",
      nullptr));
#endif
}

FlMethodResponse* recognize_text_from_bytes(FlValue* args) {
  if (!args || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
    return FL_METHOD_RESPONSE(fl_method_error_response_new(
        "INVALID_ARGUMENT", "Missing or invalid arguments map.", nullptr));
  }

  FlValue* bytes_v = fl_value_lookup_string(args, "imageBytes");
  if (!bytes_v || fl_value_get_type(bytes_v) != FL_VALUE_TYPE_UINT8_LIST) {
    return FL_METHOD_RESPONSE(fl_method_error_response_new(
        "INVALID_ARGUMENT", "Missing or invalid 'imageBytes'.", nullptr));
  }

#if HAS_TESSERACT
  const std::string lang = BuildTessLang(args);
  const uint8_t* data = fl_value_get_uint8_list(bytes_v);
  const size_t len = fl_value_get_length(bytes_v);
  if (!data || len == 0) {
    return FL_METHOD_RESPONSE(fl_method_error_response_new(
        "INVALID_ARGUMENT", "Missing or invalid 'imageBytes'.", nullptr));
  }
  Pix* pix = pixReadMem(data, static_cast<int>(len));
  return TessOcrPix(pix, lang);
#else
  return FL_METHOD_RESPONSE(fl_method_error_response_new(
      "UNAVAILABLE",
      "Tesseract/Leptonica not found. Install libtesseract-dev and libleptonica-dev then rebuild.",
      nullptr));
#endif
}

static void native_ocr_plugin_dispose(GObject* object) {
  G_OBJECT_CLASS(native_ocr_plugin_parent_class)->dispose(object);
}

static void native_ocr_plugin_class_init(NativeOcrPluginClass* klass) {
  G_OBJECT_CLASS(klass)->dispose = native_ocr_plugin_dispose;
}

static void native_ocr_plugin_init(NativeOcrPlugin* self) {}

static void method_call_cb(FlMethodChannel* channel, FlMethodCall* method_call,
                           gpointer user_data) {
  NativeOcrPlugin* plugin = NATIVE_OCR_PLUGIN(user_data);
  native_ocr_plugin_handle_method_call(plugin, method_call);
}

void native_ocr_plugin_register_with_registrar(FlPluginRegistrar* registrar) {
  NativeOcrPlugin* plugin = NATIVE_OCR_PLUGIN(
      g_object_new(native_ocr_plugin_get_type(), nullptr));

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) channel =
      fl_method_channel_new(fl_plugin_registrar_get_messenger(registrar),
                            "native_ocr",
                            FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel, method_call_cb,
                                            g_object_ref(plugin),
                                            g_object_unref);

  g_object_unref(plugin);
}
