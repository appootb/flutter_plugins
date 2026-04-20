#include "include/file_preview_plus/file_preview_plus_plugin.h"

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>
#include <gio/gio.h>
#include <sys/utsname.h>

#include <algorithm>
#include <cstring>
#include <optional>
#include <vector>

#include "file_preview_plus_plugin_private.h"

#define FILE_PREVIEW_PLUS_PLUGIN(obj) \
  (G_TYPE_CHECK_INSTANCE_CAST((obj), file_preview_plus_plugin_get_type(), \
                              FilePreviewPlusPlugin))

struct _FilePreviewPlusPlugin {
  GObject parent_instance;
};

G_DEFINE_TYPE(FilePreviewPlusPlugin, file_preview_plus_plugin, g_object_get_type())

namespace {

FlValue* map_get(FlValue* map, const gchar* key) {
  if (map == nullptr || fl_value_get_type(map) != FL_VALUE_TYPE_MAP) return nullptr;
  return fl_value_lookup_string(map, key);
}

const gchar* map_get_string(FlValue* map, const gchar* key) {
  FlValue* v = map_get(map, key);
  if (v == nullptr || fl_value_get_type(v) != FL_VALUE_TYPE_STRING) return nullptr;
  return fl_value_get_string(v);
}

int map_get_int(FlValue* map, const gchar* key, int def) {
  FlValue* v = map_get(map, key);
  if (v == nullptr) return def;
  if (fl_value_get_type(v) == FL_VALUE_TYPE_INT) return static_cast<int>(fl_value_get_int(v));
  return def;
}

gboolean file_exists(const gchar* path) {
  if (path == nullptr) return FALSE;
  return g_file_test(path, G_FILE_TEST_EXISTS);
}

FlMethodResponse* success_map(FlValue* map) {
  return FL_METHOD_RESPONSE(fl_method_success_response_new(map));
}

FlMethodResponse* success_bytes(const guint8* bytes, gsize len) {
  g_autoptr(FlValue) v = fl_value_new_uint8_list(bytes, len);
  return FL_METHOD_RESPONSE(fl_method_success_response_new(v));
}

FlMethodResponse* success_null() {
  return FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
}

FlMethodResponse* error_response(const gchar* code, const gchar* message) {
  return FL_METHOD_RESPONSE(fl_method_error_response_new(code, message, nullptr));
}

GFileInfo* query_info(GFile* file) {
  return g_file_query_info(
      file,
      "standard::name,standard::display-name,standard::size,standard::content-type,standard::type,standard::icon,time::modified,time::created,thumbnail::path",
      G_FILE_QUERY_INFO_NONE,
      nullptr,
      nullptr);
}

GdkPixbuf* load_icon_pixbuf(GIcon* icon, int size) {
  if (icon == nullptr) return nullptr;
  GtkIconTheme* theme = gtk_icon_theme_get_default();
  if (theme == nullptr) return nullptr;

  // Prefer themed icon names if available.
  if (G_IS_THEMED_ICON(icon)) {
    gchar** names = g_themed_icon_get_names(G_THEMED_ICON(icon));
    if (names != nullptr) {
      for (int i = 0; names[i] != nullptr; i++) {
        if (gtk_icon_theme_has_icon(theme, names[i])) {
          return gtk_icon_theme_load_icon(theme, names[i], size, GTK_ICON_LOOKUP_FORCE_SIZE, nullptr);
        }
      }
    }
  }

  return nullptr;
}

std::optional<std::vector<guint8>> pixbuf_to_png_bytes(GdkPixbuf* pixbuf) {
  if (pixbuf == nullptr) return std::nullopt;
  gchar* buffer = nullptr;
  gsize len = 0;
  if (!gdk_pixbuf_save_to_buffer(pixbuf, &buffer, &len, "png", nullptr, nullptr)) {
    return std::nullopt;
  }
  std::vector<guint8> out(len);
  memcpy(out.data(), buffer, len);
  g_free(buffer);
  return out;
}

}  // namespace

// Called when a method call is received from Flutter.
static void file_preview_plus_plugin_handle_method_call(
    FilePreviewPlusPlugin* self,
    FlMethodCall* method_call) {
  g_autoptr(FlMethodResponse) response = nullptr;

  const gchar* method = fl_method_call_get_name(method_call);
  FlValue* args = fl_method_call_get_args(method_call);

  if (strcmp(method, "getPlatformVersion") == 0) {
    response = get_platform_version();
  } else if (strcmp(method, "getFileInfo") == 0) {
    const gchar* path = map_get_string(args, "path");
    response = get_file_info(path);
  } else if (strcmp(method, "getThumbnail") == 0) {
    const gchar* path = map_get_string(args, "path");
    int width = map_get_int(args, "width", 256);
    int height = map_get_int(args, "height", 256);
    response = get_thumbnail(path, width, height);
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

FlMethodResponse* get_file_info(const gchar* path) {
  if (path == nullptr || *path == '\0') {
    return error_response("invalid_args", "Missing path");
  }

  g_autoptr(GFile) file = g_file_new_for_path(path);
  g_autoptr(GFileInfo) info = query_info(file);
  if (info == nullptr) {
    // Return minimal info even if query fails.
    g_autoptr(FlValue) map = fl_value_new_map();
    fl_value_set_string_take(map, "path", fl_value_new_string(path));
    return success_map(map);
  }

  g_autoptr(FlValue) map = fl_value_new_map();
  fl_value_set_string_take(map, "path", fl_value_new_string(path));

  const gchar* name = g_file_info_get_name(info);
  if (name != nullptr) fl_value_set_string_take(map, "name", fl_value_new_string(name));

  goffset size = g_file_info_get_size(info);
  fl_value_set_string_take(map, "size", fl_value_new_int(size));

  GFileType type = g_file_info_get_file_type(info);
  fl_value_set_string_take(map, "isDirectory", fl_value_new_bool(type == G_FILE_TYPE_DIRECTORY));

  const gchar* content_type = g_file_info_get_content_type(info);
  if (content_type != nullptr) {
    fl_value_set_string_take(map, "mimeType", fl_value_new_string(content_type));
  }

  // modifiedMs
  if (g_file_info_has_attribute(info, G_FILE_ATTRIBUTE_TIME_MODIFIED)) {
    guint64 sec = g_file_info_get_attribute_uint64(info, G_FILE_ATTRIBUTE_TIME_MODIFIED);
    fl_value_set_string_take(map, "modifiedMs", fl_value_new_int(static_cast<int64_t>(sec) * 1000));
  }
  // createdMs (if available)
  if (g_file_info_has_attribute(info, G_FILE_ATTRIBUTE_TIME_CREATED)) {
    guint64 sec = g_file_info_get_attribute_uint64(info, G_FILE_ATTRIBUTE_TIME_CREATED);
    fl_value_set_string_take(map, "createdMs", fl_value_new_int(static_cast<int64_t>(sec) * 1000));
  }

  return success_map(map);
}

FlMethodResponse* get_thumbnail(const gchar* path, int width, int height) {
  if (path == nullptr || *path == '\0') {
    return error_response("invalid_args", "Missing path");
  }
  width = std::max(1, width);
  height = std::max(1, height);
  const int icon_size = std::max(width, height);

  g_autoptr(GFile) file = g_file_new_for_path(path);
  g_autoptr(GFileInfo) info = query_info(file);
  if (info != nullptr) {
    const gchar* thumb_path =
        g_file_info_get_attribute_byte_string(info, G_FILE_ATTRIBUTE_THUMBNAIL_PATH);
    if (thumb_path != nullptr && file_exists(thumb_path)) {
      g_autofree gchar* data = nullptr;
      gsize len = 0;
      if (g_file_get_contents(thumb_path, &data, &len, nullptr) && data != nullptr && len > 0) {
        return success_bytes(reinterpret_cast<const guint8*>(data), len);
      }
    }

    // Fallback to themed icon.
    GIcon* icon = g_file_info_get_icon(info);
    g_autoptr(GdkPixbuf) pix = load_icon_pixbuf(icon, icon_size);
    if (pix != nullptr) {
      auto png = pixbuf_to_png_bytes(pix);
      if (png) return success_bytes(png->data(), png->size());
    }
  }

  return success_null();
}

static void file_preview_plus_plugin_dispose(GObject* object) {
  G_OBJECT_CLASS(file_preview_plus_plugin_parent_class)->dispose(object);
}

static void file_preview_plus_plugin_class_init(FilePreviewPlusPluginClass* klass) {
  G_OBJECT_CLASS(klass)->dispose = file_preview_plus_plugin_dispose;
}

static void file_preview_plus_plugin_init(FilePreviewPlusPlugin* self) {}

static void method_call_cb(FlMethodChannel* channel, FlMethodCall* method_call,
                           gpointer user_data) {
  FilePreviewPlusPlugin* plugin = FILE_PREVIEW_PLUS_PLUGIN(user_data);
  file_preview_plus_plugin_handle_method_call(plugin, method_call);
}

void file_preview_plus_plugin_register_with_registrar(FlPluginRegistrar* registrar) {
  FilePreviewPlusPlugin* plugin = FILE_PREVIEW_PLUS_PLUGIN(
      g_object_new(file_preview_plus_plugin_get_type(), nullptr));

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) channel =
      fl_method_channel_new(fl_plugin_registrar_get_messenger(registrar),
                            "file_preview_plus",
                            FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel, method_call_cb,
                                            g_object_ref(plugin),
                                            g_object_unref);

  g_object_unref(plugin);
}
