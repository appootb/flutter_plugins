#include "include/desktop_auto_launch/desktop_auto_launch_plugin.h"

#include <flutter_linux/flutter_linux.h>
#include <sys/utsname.h>

#include <gio/gio.h>

#include <cstring>
#include <string>
#include <cerrno>

#include "desktop_auto_launch_plugin_private.h"

#define DESKTOP_AUTO_LAUNCH_PLUGIN(obj) \
  (G_TYPE_CHECK_INSTANCE_CAST((obj), desktop_auto_launch_plugin_get_type(), \
                              DesktopAutoLaunchPlugin))

struct _DesktopAutoLaunchPlugin {
  GObject parent_instance;
};

G_DEFINE_TYPE(DesktopAutoLaunchPlugin, desktop_auto_launch_plugin, g_object_get_type())

namespace {

gchar* sanitize_app_id(const gchar* app_name) {
  if (app_name == nullptr || *app_name == '\0') {
    return g_strdup("app");
  }
  GString* out = g_string_new(nullptr);
  for (const gchar* p = app_name; *p != '\0'; ++p) {
    const gunichar c = g_utf8_get_char(p);
    if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
        (c >= '0' && c <= '9') || c == '_' || c == '-') {
      g_string_append_unichar(out, c);
    } else {
      g_string_append_c(out, '_');
    }
    // Advance by UTF-8 char length.
    p += (g_utf8_next_char(p) - p) - 1;
  }
  return g_string_free(out, FALSE);
}

constexpr const char* kInvalidArgument = "INVALID_ARGUMENT";
constexpr const char* kAutoStartError = "AUTO_START_ERROR";

gchar* autostart_desktop_path_for_app(const gchar* app_name) {
  g_autofree gchar* safe = sanitize_app_id(app_name);
  const gchar* config_dir = g_get_user_config_dir();  // ~/.config
  g_autofree gchar* autostart_dir = g_build_filename(config_dir, "autostart", nullptr);
  g_mkdir_with_parents(autostart_dir, 0755);
  return g_build_filename(autostart_dir, (std::string(safe) + ".desktop").c_str(), nullptr);
}

gchar* get_self_exe_path() {
  // Prefer /proc/self/exe
  GError* error = nullptr;
  gchar* link = g_file_read_link("/proc/self/exe", &error);
  if (error != nullptr) {
    g_error_free(error);
  }
  return link;  // may be nullptr
}

}  // namespace

// Called when a method call is received from Flutter.
static void desktop_auto_launch_plugin_handle_method_call(
    DesktopAutoLaunchPlugin* self,
    FlMethodCall* method_call) {
  g_autoptr(FlMethodResponse) response = nullptr;

  const gchar* method = fl_method_call_get_name(method_call);

  if (strcmp(method, "getPlatformVersion") == 0) {
    response = get_platform_version();
  } else if (strcmp(method, "isEnabled") == 0) {
    // Require appName to make the result deterministic.
    FlValue* args = fl_method_call_get_args(method_call);
    if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
      response = FL_METHOD_RESPONSE(fl_method_error_response_new(
          kInvalidArgument, "Missing arguments.", nullptr));
      fl_method_call_respond(method_call, response, nullptr);
      return;
    }
    FlValue* app_name_val = fl_value_lookup_string(args, "appName");
    if (app_name_val == nullptr || fl_value_get_type(app_name_val) != FL_VALUE_TYPE_STRING) {
      response = FL_METHOD_RESPONSE(fl_method_error_response_new(
          kInvalidArgument, "Missing `appName`.", nullptr));
      fl_method_call_respond(method_call, response, nullptr);
      return;
    }
    const gchar* app_name = fl_value_get_string(app_name_val);
    g_autofree gchar* desktop_path = autostart_desktop_path_for_app(app_name);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(
        fl_value_new_bool(g_file_test(desktop_path, G_FILE_TEST_EXISTS))));
  } else if (strcmp(method, "setEnabled") == 0) {
    FlValue* args = fl_method_call_get_args(method_call);
    if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
      response = FL_METHOD_RESPONSE(fl_method_error_response_new(
          kInvalidArgument, "Missing arguments.", nullptr));
      fl_method_call_respond(method_call, response, nullptr);
      return;
    }

    FlValue* enabled_val = fl_value_lookup_string(args, "enabled");
    FlValue* app_val = fl_value_lookup_string(args, "app");
    if (enabled_val == nullptr || fl_value_get_type(enabled_val) != FL_VALUE_TYPE_BOOL) {
      response = FL_METHOD_RESPONSE(fl_method_error_response_new(
          kInvalidArgument, "Missing `enabled`.", nullptr));
      fl_method_call_respond(method_call, response, nullptr);
      return;
    }
    const gboolean enabled = fl_value_get_bool(enabled_val);

    if (app_val == nullptr || fl_value_get_type(app_val) != FL_VALUE_TYPE_MAP) {
      response = FL_METHOD_RESPONSE(fl_method_error_response_new(
          kInvalidArgument, "Missing `app`.", nullptr));
      fl_method_call_respond(method_call, response, nullptr);
      return;
    }

    FlValue* app_name_val = fl_value_lookup_string(app_val, "appName");
    if (app_name_val == nullptr || fl_value_get_type(app_name_val) != FL_VALUE_TYPE_STRING) {
      response = FL_METHOD_RESPONSE(fl_method_error_response_new(
          kInvalidArgument, "Missing `app.appName`.", nullptr));
      fl_method_call_respond(method_call, response, nullptr);
      return;
    }
    const gchar* app_name = fl_value_get_string(app_name_val);
    if (app_name == nullptr || *app_name == '\0') {
      response = FL_METHOD_RESPONSE(fl_method_error_response_new(
          kInvalidArgument, "Missing `app.appName`.", nullptr));
      fl_method_call_respond(method_call, response, nullptr);
      return;
    }

    g_autofree gchar* desktop_path = autostart_desktop_path_for_app(app_name);

    if (!enabled) {
      // Disable: delete file if it exists.
      if (g_remove(desktop_path) == 0 || errno == ENOENT) {
        response = FL_METHOD_RESPONSE(fl_method_success_response_new(fl_value_new_bool(TRUE)));
      } else {
        response = FL_METHOD_RESPONSE(fl_method_error_response_new(
            kAutoStartError, "Failed to remove autostart entry.", nullptr));
      }
      fl_method_call_respond(method_call, response, nullptr);
      return;
    }

    // Enable: write ~/.config/autostart/<app>.desktop
    g_autofree gchar* exe_path = get_self_exe_path();
    if (exe_path == nullptr) {
      response = FL_METHOD_RESPONSE(fl_method_error_response_new(
          kAutoStartError, "Failed to resolve executable path.", nullptr));
      fl_method_call_respond(method_call, response, nullptr);
      return;
    }

    g_autoptr(GKeyFile) key_file = g_key_file_new();
    g_key_file_set_string(key_file, "Desktop Entry", "Type", "Application");
    g_key_file_set_string(key_file, "Desktop Entry", "Name", app_name);

    // Quote exec path to preserve spaces.
    g_autofree gchar* quoted_exec = g_shell_quote(exe_path);
    g_key_file_set_string(key_file, "Desktop Entry", "Exec", quoted_exec);

    g_key_file_set_boolean(key_file, "Desktop Entry", "X-GNOME-Autostart-enabled", TRUE);
    g_key_file_set_boolean(key_file, "Desktop Entry", "NoDisplay", FALSE);

    gsize data_len = 0;
    GError* error = nullptr;
    g_autofree gchar* data = g_key_file_to_data(key_file, &data_len, &error);
    if (error != nullptr || data == nullptr) {
      if (error != nullptr) g_error_free(error);
      response = FL_METHOD_RESPONSE(fl_method_error_response_new(
          kAutoStartError, "Failed to serialize desktop entry.", nullptr));
      fl_method_call_respond(method_call, response, nullptr);
      return;
    }

    if (!g_file_set_contents(desktop_path, data, (gssize)data_len, &error)) {
      const gchar* msg = error != nullptr ? error->message : nullptr;
      if (error != nullptr) g_error_free(error);
      response = FL_METHOD_RESPONSE(fl_method_error_response_new(
          kAutoStartError, "Failed to write autostart entry.", msg));
      fl_method_call_respond(method_call, response, nullptr);
      return;
    }

    response = FL_METHOD_RESPONSE(fl_method_success_response_new(fl_value_new_bool(TRUE)));
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

static void desktop_auto_launch_plugin_dispose(GObject* object) {
  G_OBJECT_CLASS(desktop_auto_launch_plugin_parent_class)->dispose(object);
}

static void desktop_auto_launch_plugin_class_init(DesktopAutoLaunchPluginClass* klass) {
  G_OBJECT_CLASS(klass)->dispose = desktop_auto_launch_plugin_dispose;
}

static void desktop_auto_launch_plugin_init(DesktopAutoLaunchPlugin* self) {}

static void method_call_cb(FlMethodChannel* channel, FlMethodCall* method_call,
                           gpointer user_data) {
  DesktopAutoLaunchPlugin* plugin = DESKTOP_AUTO_LAUNCH_PLUGIN(user_data);
  desktop_auto_launch_plugin_handle_method_call(plugin, method_call);
}

void desktop_auto_launch_plugin_register_with_registrar(FlPluginRegistrar* registrar) {
  DesktopAutoLaunchPlugin* plugin = DESKTOP_AUTO_LAUNCH_PLUGIN(
      g_object_new(desktop_auto_launch_plugin_get_type(), nullptr));

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) channel =
      fl_method_channel_new(fl_plugin_registrar_get_messenger(registrar),
                            "desktop_auto_launch",
                            FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel, method_call_cb,
                                            g_object_ref(plugin),
                                            g_object_unref);

  g_object_unref(plugin);
}
