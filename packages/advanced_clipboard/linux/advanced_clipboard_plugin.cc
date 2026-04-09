#include "include/advanced_clipboard/advanced_clipboard_plugin.h"

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>
#include <sys/utsname.h>

#include <X11/Xlib.h>
#include <X11/Xatom.h>
#include <limits.h>
#include <unistd.h>

#include <cstring>

#include "advanced_clipboard_plugin_private.h"

#define ADVANCED_CLIPBOARD_PLUGIN(obj) \
  (G_TYPE_CHECK_INSTANCE_CAST((obj), advanced_clipboard_plugin_get_type(), \
                              AdvancedClipboardPlugin))

struct _AdvancedClipboardPlugin {
  GObject parent_instance;

  FlMethodChannel* method_channel;
  FlEventChannel* event_channel;

  gboolean is_listening;
  guint timeout_id;

  // Signature of last clipboard contents to detect changes.
  gchar* last_signature;
  gboolean ignore_next_change;
  guint64 sequence;

  // Cached last non-self foreground application info (similar to macOS).
  pid_t self_pid;
  gchar* cached_app_name;
  gchar* cached_bundle_id;
  guchar* cached_icon_png;
  gsize cached_icon_size;
  gboolean has_cached_app;
};

static gboolean advanced_clipboard_check_clipboard(gpointer user_data);
static void advanced_clipboard_start_monitoring(AdvancedClipboardPlugin* self);
static void advanced_clipboard_stop_monitoring(AdvancedClipboardPlugin* self);
static gboolean advanced_clipboard_write(AdvancedClipboardPlugin* self,
                                         FlMethodCall* method_call,
                                         FlMethodResponse** response_out);
static gboolean advanced_clipboard_get_window_icon(Display* display,
                                                   Window window,
                                                   guchar** out_png,
                                                   gsize* out_size);
static FlValue* advanced_clipboard_get_source_app(AdvancedClipboardPlugin* self);

G_DEFINE_TYPE(AdvancedClipboardPlugin, advanced_clipboard_plugin, g_object_get_type())

static void advanced_clipboard_plugin_handle_method_call(
    AdvancedClipboardPlugin* self,
    FlMethodCall* method_call) {
  g_autoptr(FlMethodResponse) response = nullptr;

  const gchar* method = fl_method_call_get_name(method_call);

  if (strcmp(method, "getPlatformVersion") == 0) {
    response = get_platform_version();
  } else if (strcmp(method, "startListening") == 0) {
    advanced_clipboard_start_monitoring(self);
    g_autoptr(FlValue) result = fl_value_new_null();
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  } else if (strcmp(method, "stopListening") == 0) {
    advanced_clipboard_stop_monitoring(self);
    g_autoptr(FlValue) result = fl_value_new_null();
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  } else if (strcmp(method, "write") == 0) {
    FlMethodResponse* write_response = nullptr;
    if (advanced_clipboard_write(self, method_call, &write_response)) {
      response = write_response;
    } else {
      g_autoptr(FlValue) result = fl_value_new_bool(FALSE);
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
    }
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

static void advanced_clipboard_plugin_dispose(GObject* object) {
  AdvancedClipboardPlugin* self = ADVANCED_CLIPBOARD_PLUGIN(object);

  advanced_clipboard_stop_monitoring(self);

  if (self->method_channel != nullptr) {
    g_clear_object(&self->method_channel);
  }

  if (self->event_channel != nullptr) {
    g_clear_object(&self->event_channel);
  }

  if (self->last_signature != nullptr) {
    g_clear_pointer(&self->last_signature, g_free);
  }

  if (self->cached_app_name != nullptr) {
    g_clear_pointer(&self->cached_app_name, g_free);
  }
  if (self->cached_bundle_id != nullptr) {
    g_clear_pointer(&self->cached_bundle_id, g_free);
  }
  if (self->cached_icon_png != nullptr) {
    g_free(self->cached_icon_png);
    self->cached_icon_png = nullptr;
    self->cached_icon_size = 0;
  }

  G_OBJECT_CLASS(advanced_clipboard_plugin_parent_class)->dispose(object);
}

static void advanced_clipboard_plugin_class_init(AdvancedClipboardPluginClass* klass) {
  G_OBJECT_CLASS(klass)->dispose = advanced_clipboard_plugin_dispose;
}

static void advanced_clipboard_plugin_init(AdvancedClipboardPlugin* self) {
  self->is_listening = FALSE;
  self->timeout_id = 0;
  self->last_signature = nullptr;
  self->ignore_next_change = FALSE;
  self->sequence = 0;

  self->self_pid = getpid();
  self->cached_app_name = nullptr;
  self->cached_bundle_id = nullptr;
  self->cached_icon_png = nullptr;
  self->cached_icon_size = 0;
  self->has_cached_app = FALSE;
}

static void method_call_cb(FlMethodChannel* channel, FlMethodCall* method_call,
                           gpointer user_data) {
  AdvancedClipboardPlugin* plugin = ADVANCED_CLIPBOARD_PLUGIN(user_data);
  advanced_clipboard_plugin_handle_method_call(plugin, method_call);
}

void advanced_clipboard_plugin_register_with_registrar(FlPluginRegistrar* registrar) {
  AdvancedClipboardPlugin* plugin = ADVANCED_CLIPBOARD_PLUGIN(
      g_object_new(advanced_clipboard_plugin_get_type(), nullptr));

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) channel =
      fl_method_channel_new(fl_plugin_registrar_get_messenger(registrar),
                            "advanced_clipboard",
                            FL_METHOD_CODEC(codec));
  g_autoptr(FlEventChannel) event_channel =
      fl_event_channel_new(fl_plugin_registrar_get_messenger(registrar),
                           "advanced_clipboard_events",
                           FL_METHOD_CODEC(codec));

  plugin->method_channel =
      FL_METHOD_CHANNEL(g_object_ref(channel));
  plugin->event_channel =
      FL_EVENT_CHANNEL(g_object_ref(event_channel));

  fl_method_channel_set_method_call_handler(channel, method_call_cb,
                                            g_object_ref(plugin),
                                            g_object_unref);

  fl_event_channel_set_stream_handlers(
      event_channel,
      [](FlEventChannel* channel, FlValue* args,
         gpointer user_data) -> FlMethodErrorResponse* {
        AdvancedClipboardPlugin* self =
            ADVANCED_CLIPBOARD_PLUGIN(user_data);
        self->is_listening = TRUE;
        return nullptr;
      },
      [](FlEventChannel* channel, FlValue* args,
         gpointer user_data) -> FlMethodErrorResponse* {
        AdvancedClipboardPlugin* self =
            ADVANCED_CLIPBOARD_PLUGIN(user_data);
        self->is_listening = FALSE;
        if (self->timeout_id != 0) {
          g_source_remove(self->timeout_id);
          self->timeout_id = 0;
        }
        return nullptr;
      },
      g_object_ref(plugin),
      g_object_unref);

  g_object_unref(plugin);
}

static void advanced_clipboard_start_monitoring(AdvancedClipboardPlugin* self) {
  if (self->is_listening && self->timeout_id != 0) {
    return;
  }

  self->is_listening = TRUE;

  if (self->last_signature != nullptr) {
    g_clear_pointer(&self->last_signature, g_free);
  }

  if (self->timeout_id == 0) {
    g_object_ref(self);
    self->timeout_id =
        g_timeout_add_full(G_PRIORITY_DEFAULT, 250,
                           advanced_clipboard_check_clipboard,
                           self,
                           [](gpointer data) {
                             AdvancedClipboardPlugin* self_local =
                                 ADVANCED_CLIPBOARD_PLUGIN(data);
                             g_object_unref(self_local);
                           });
  }
}

static void advanced_clipboard_stop_monitoring(AdvancedClipboardPlugin* self) {
  self->is_listening = FALSE;
  if (self->timeout_id != 0) {
    g_source_remove(self->timeout_id);
    self->timeout_id = 0;
  }
}

static gboolean advanced_clipboard_check_clipboard(gpointer user_data) {
  AdvancedClipboardPlugin* self =
      ADVANCED_CLIPBOARD_PLUGIN(user_data);

  if (!self->is_listening || self->event_channel == nullptr) {
    return G_SOURCE_CONTINUE;
  }

  GtkClipboard* clipboard = gtk_clipboard_get(GDK_SELECTION_CLIPBOARD);
  if (clipboard == nullptr) {
    return G_SOURCE_CONTINUE;
  }

  // Read text.
  gchar* text = gtk_clipboard_wait_for_text(clipboard);

  // Read HTML.
  GtkSelectionData* html_data = nullptr;
  GdkAtom html_atom = gdk_atom_intern("text/html", FALSE);
  if (html_atom != GDK_NONE) {
    html_data = gtk_clipboard_wait_for_contents(clipboard, html_atom);
  }

  // Read image.
  GdkPixbuf* image = gtk_clipboard_wait_for_image(clipboard);

  // Read file URIs.
  GtkSelectionData* uri_data = nullptr;
  GdkAtom uri_atom = gdk_atom_intern("text/uri-list", FALSE);
  if (uri_atom != GDK_NONE) {
    uri_data = gtk_clipboard_wait_for_contents(clipboard, uri_atom);
  }

  // Build a simple signature string to detect changes.
  GString* sig = g_string_new(nullptr);

  if (text != nullptr && *text != '\0') {
    g_string_append(sig, "T:");
    g_string_append_len(sig, text, MIN(strlen(text), (gsize)256));
  } else {
    g_string_append(sig, "T:");
  }

  if (html_data != nullptr &&
      gtk_selection_data_get_length(html_data) > 0) {
    const guchar* hbytes = gtk_selection_data_get_data(html_data);
    gint hlen = gtk_selection_data_get_length(html_data);
    g_string_append(sig, "|H:");
    if (hbytes != nullptr && hlen > 0) {
      g_string_append_len(sig,
                          (const gchar*)hbytes,
                          MIN((gsize)hlen, (gsize)256));
    }
  } else {
    g_string_append(sig, "|H:");
  }

  if (image != nullptr) {
    // Do not depend on pixel dimensions in the signature.
    g_string_append(sig, "|I:1");
  } else {
    g_string_append(sig, "|I:");
  }

  if (uri_data != nullptr &&
      gtk_selection_data_get_length(uri_data) > 0) {
    const gchar* uris =
        (const gchar*)gtk_selection_data_get_data(uri_data);
    g_string_append(sig, "|U:");
    if (uris != nullptr) {
      g_string_append_len(sig, uris,
                          MIN(strlen(uris), (gsize)256));
    }
  } else {
    g_string_append(sig, "|U:");
  }

  gboolean changed = FALSE;
  if (self->last_signature == nullptr) {
    changed = TRUE;
  } else if (g_strcmp0(self->last_signature, sig->str) != 0) {
    changed = TRUE;
  }

  if (self->ignore_next_change) {
    self->ignore_next_change = FALSE;
    if (self->last_signature != nullptr) {
      g_free(self->last_signature);
    }
    self->last_signature = g_string_free(sig, FALSE);

    if (html_data != nullptr) {
      gtk_selection_data_free(html_data);
    }
    if (image != nullptr) {
      g_object_unref(image);
    }
    if (uri_data != nullptr) {
      gtk_selection_data_free(uri_data);
    }
    if (text != nullptr) {
      g_free(text);
    }
    return G_SOURCE_CONTINUE;
  }

  if (!changed) {
    g_string_free(sig, TRUE);
    if (html_data != nullptr) {
      gtk_selection_data_free(html_data);
    }
    if (image != nullptr) {
      g_object_unref(image);
    }
    if (uri_data != nullptr) {
      gtk_selection_data_free(uri_data);
    }
    if (text != nullptr) {
      g_free(text);
    }
    return G_SOURCE_CONTINUE;
  }

  if (self->last_signature != nullptr) {
    g_free(self->last_signature);
  }
  self->last_signature = g_string_free(sig, FALSE);

  // Build ClipboardEntry.
  gint64 timestamp_ms = g_get_real_time() / 1000;

  g_autoptr(FlValue) entry = fl_value_new_map();

  fl_value_set_string(entry, "timestamp",
                      fl_value_new_int(timestamp_ms));

  FlValue* source_app = advanced_clipboard_get_source_app(self);
  fl_value_set_string(entry, "sourceApp", source_app);

  FlValue* contents = fl_value_new_list();

  // Text & URL.
  if (text != nullptr && *text != '\0') {
    gsize len = strlen(text);
    FlValue* raw = fl_value_new_uint8_list(
        reinterpret_cast<const uint8_t*>(text), len);

    FlValue* text_part = fl_value_new_map();
    fl_value_set_string(text_part, "type",
                        fl_value_new_string("text"));
    fl_value_set_string(text_part, "raw", raw);
    fl_value_set_string(text_part, "metadata",
                        fl_value_new_null());
    fl_value_append(contents, text_part);

    if (g_str_has_prefix(text, "http://") ||
        g_str_has_prefix(text, "https://")) {
      FlValue* url_raw = fl_value_new_uint8_list(
          reinterpret_cast<const uint8_t*>(text), len);
      FlValue* url_part = fl_value_new_map();
      fl_value_set_string(url_part, "type",
                          fl_value_new_string("url"));
      fl_value_set_string(url_part, "raw", url_raw);
      fl_value_set_string(url_part, "metadata",
                          fl_value_new_null());
      fl_value_append(contents, url_part);
    }
  }

  // HTML.
  if (html_data != nullptr &&
      gtk_selection_data_get_length(html_data) > 0) {
    const guchar* hbytes = gtk_selection_data_get_data(html_data);
    gint hlen = gtk_selection_data_get_length(html_data);
    if (hbytes != nullptr && hlen > 0) {
      FlValue* raw = fl_value_new_uint8_list(hbytes, (gsize)hlen);
      FlValue* html_part = fl_value_new_map();
      fl_value_set_string(html_part, "type",
                          fl_value_new_string("html"));
      fl_value_set_string(html_part, "raw", raw);
      fl_value_set_string(html_part, "metadata",
                          fl_value_new_null());
      fl_value_append(contents, html_part);
    }
  }

  // Image (PNG).
  if (image != nullptr) {
    gchar* png_buf = nullptr;
    gsize png_size = 0;
    GError* img_error = nullptr;
    if (gdk_pixbuf_save_to_buffer(image,
                                  &png_buf,
                                  &png_size,
                                  "png",
                                  &img_error,
                                  nullptr)) {
      FlValue* raw = fl_value_new_uint8_list(
          reinterpret_cast<const guchar*>(png_buf),
          png_size);

      FlValue* meta = fl_value_new_map();
      fl_value_set_string(meta, "format",
                          fl_value_new_string("png"));

      FlValue* image_part = fl_value_new_map();
      fl_value_set_string(image_part, "type",
                          fl_value_new_string("image"));
      fl_value_set_string(image_part, "raw", raw);
      fl_value_set_string(image_part, "metadata", meta);
      fl_value_append(contents, image_part);
    }
    if (img_error != nullptr) {
      g_error_free(img_error);
    }
    g_free(png_buf);
  }

  // Files (text/uri-list).
  if (uri_data != nullptr &&
      gtk_selection_data_get_length(uri_data) > 0) {
    const gchar* uris =
        (const gchar*)gtk_selection_data_get_data(uri_data);
    if (uris != nullptr) {
      gchar** lines = g_strsplit(uris, "\n", -1);
      // Collect all file paths to optionally synthesize a plain-text
      // representation (one path per line) when there is no text/plain.
      GString* file_text = g_string_new(nullptr);
      for (gint i = 0; lines[i] != nullptr; ++i) {
        const gchar* line = lines[i];
        if (line[0] == '\0' || line[0] == '#') {
          continue;
        }
        gchar* path = g_filename_from_uri(line, nullptr, nullptr);
        if (path == nullptr) {
          continue;
        }

        gboolean is_dir =
            g_file_test(path, G_FILE_TEST_IS_DIR);

        FlValue* raw = fl_value_new_uint8_list(
            reinterpret_cast<const guchar*>(path),
            strlen(path));

        FlValue* meta = fl_value_new_map();
        fl_value_set_string(meta, "isDirectory",
                            fl_value_new_bool(is_dir));

        FlValue* file_part = fl_value_new_map();
        fl_value_set_string(file_part, "type",
                            fl_value_new_string("fileUrl"));
        fl_value_set_string(file_part, "raw", raw);
        fl_value_set_string(file_part, "metadata", meta);
        fl_value_append(contents, file_part);

        // Build newline-separated plain-text of file paths.
        if (file_text->len > 0) {
          g_string_append_c(file_text, '\n');
        }
        g_string_append(file_text, path);

        g_free(path);
      }
      g_strfreev(lines);

      // If there was no text/plain on the clipboard, also expose the file
      // paths as a single "text" part (one path per line), to mirror
      // macOS/Windows behavior where copy-file gives both fileUrl and text.
      if (file_text->len > 0 && (text == nullptr || *text == '\0')) {
        FlValue* raw = fl_value_new_uint8_list(
            reinterpret_cast<const guchar*>(file_text->str),
            file_text->len);
        FlValue* text_part = fl_value_new_map();
        fl_value_set_string(text_part, "type",
                            fl_value_new_string("text"));
        fl_value_set_string(text_part, "raw", raw);
        fl_value_set_string(text_part, "metadata",
                            fl_value_new_null());
        fl_value_append(contents, text_part);
      }

      g_string_free(file_text, TRUE);
    }
  }

  // Free temporary clipboard data objects.
  if (html_data != nullptr) {
    gtk_selection_data_free(html_data);
  }
  if (image != nullptr) {
    g_object_unref(image);
  }
  if (uri_data != nullptr) {
    gtk_selection_data_free(uri_data);
  }
  if (text != nullptr) {
    g_free(text);
  }

  // If we didn't recognize any contents, don't send an event.
  if (fl_value_get_length(contents) == 0) {
    return G_SOURCE_CONTINUE;
  }

  fl_value_set_string(entry, "contents", contents);

  self->sequence += 1;
  gchar* seq_str = g_strdup_printf("%" G_GUINT64_FORMAT,
                                   self->sequence);
  fl_value_set_string(entry, "uniqueIdentifier",
                      fl_value_new_string(seq_str));
  g_free(seq_str);

  g_autoptr(GError) error = nullptr;
  if (!fl_event_channel_send(self->event_channel,
                             entry,
                             nullptr,
                             &error)) {
    if (error != nullptr) {
      g_warning("Failed to send clipboard event: %s",
                error->message);
    }
  }

  return G_SOURCE_CONTINUE;
}

static gboolean advanced_clipboard_write(AdvancedClipboardPlugin* self,
                                         FlMethodCall* method_call,
                                         FlMethodResponse** response_out) {
  FlValue* args = fl_method_call_get_args(method_call);
  if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
    g_autoptr(FlValue) result = fl_value_new_bool(FALSE);
    *response_out =
        FL_METHOD_RESPONSE(fl_method_success_response_new(result));
    return TRUE;
  }

  FlValue* contents_value =
      fl_value_lookup_string(args, "contents");
  if (contents_value == nullptr ||
      fl_value_get_type(contents_value) != FL_VALUE_TYPE_LIST) {
    g_autoptr(FlValue) result = fl_value_new_bool(FALSE);
    *response_out =
        FL_METHOD_RESPONSE(fl_method_success_response_new(result));
    return TRUE;
  }

  gboolean wrote = FALSE;

  for (size_t i = 0;
       i < fl_value_get_length(contents_value);
       i++) {
    FlValue* item =
        fl_value_get_list_value(contents_value, i);
    if (fl_value_get_type(item) != FL_VALUE_TYPE_MAP) {
      continue;
    }

    FlValue* type_value =
        fl_value_lookup_string(item, "type");
    FlValue* raw_value =
        fl_value_lookup_string(item, "raw");
    if (type_value == nullptr ||
        raw_value == nullptr ||
        fl_value_get_type(type_value) != FL_VALUE_TYPE_STRING ||
        fl_value_get_type(raw_value) !=
            FL_VALUE_TYPE_UINT8_LIST) {
      continue;
    }

    const gchar* type = fl_value_get_string(type_value);
    size_t length = fl_value_get_length(raw_value);
    const uint8_t* data = fl_value_get_uint8_list(raw_value);
    if (data == nullptr || length == 0) {
      continue;
    }

    if (g_strcmp0(type, "text") != 0 &&
        g_strcmp0(type, "url") != 0 &&
        g_strcmp0(type, "fileUrl") != 0) {
      continue;
    }

    // For Linux, treat "text", "url", and "fileUrl" all as textual data
    // when writing back to the clipboard. This ensures that copying a
    // file (fileUrl) also produces a plain-text path representation,
    // similar to macOS/Windows behavior.
    gchar* text = g_strndup(
        reinterpret_cast<const gchar*>(data), length);

    GtkClipboard* clipboard =
        gtk_clipboard_get(GDK_SELECTION_CLIPBOARD);
    if (clipboard != nullptr && text != nullptr) {
      self->ignore_next_change = TRUE;
      gtk_clipboard_set_text(clipboard, text, -1);
      gtk_clipboard_store(clipboard);
      wrote = TRUE;
    }

    g_free(text);

    if (wrote) {
      break;
    }
  }

  g_autoptr(FlValue) result = fl_value_new_bool(wrote);
  *response_out =
      FL_METHOD_RESPONSE(fl_method_success_response_new(result));

  return TRUE;
}

static FlValue* advanced_clipboard_get_source_app(AdvancedClipboardPlugin* self) {
  FlValue* map = fl_value_new_map();

  gchar* app_name = nullptr;
  gchar* bundle_id = nullptr;
  guchar* icon_png = nullptr;
  gsize icon_size = 0;
  pid_t window_pid = -1;

  Display* display = XOpenDisplay(nullptr);
  if (display != nullptr) {
    Window root = DefaultRootWindow(display);
    Atom net_active_window = XInternAtom(display, "_NET_ACTIVE_WINDOW", True);

    if (net_active_window != None) {
      Atom actual_type = None;
      int actual_format = 0;
      unsigned long nitems = 0;
      unsigned long bytes_after = 0;
      unsigned char* prop = nullptr;

      if (XGetWindowProperty(display, root, net_active_window,
                             0, 1, False, AnyPropertyType,
                             &actual_type, &actual_format,
                             &nitems, &bytes_after, &prop) == Success &&
          prop != nullptr && nitems == 1) {
        Window active = *(Window*)prop;
        XFree(prop);

        // Try to extract window icon for the active window.
        advanced_clipboard_get_window_icon(display, active,
                                           &icon_png, &icon_size);

        Atom net_wm_pid = XInternAtom(display, "_NET_WM_PID", True);
        if (net_wm_pid != None) {
          unsigned char* pid_prop = nullptr;
          nitems = 0;
          bytes_after = 0;
          actual_type = None;
          actual_format = 0;

          if (XGetWindowProperty(display, active, net_wm_pid,
                                 0, 1, False, AnyPropertyType,
                                 &actual_type, &actual_format,
                                 &nitems, &bytes_after, &pid_prop) == Success &&
              pid_prop != nullptr && nitems == 1) {
            pid_t pid = *(pid_t*)pid_prop;
            XFree(pid_prop);

            window_pid = pid;

            if (pid > 0 && pid != self->self_pid) {
              gchar path[64];
              g_snprintf(path, sizeof(path), "/proc/%d/comm", pid);
              g_file_get_contents(path, &app_name, nullptr, nullptr);
              if (app_name != nullptr) {
                g_strchomp(app_name);
              }

              g_snprintf(path, sizeof(path), "/proc/%d/exe", pid);
              gchar exe_path[PATH_MAX];
              ssize_t len = readlink(path, exe_path, sizeof(exe_path) - 1);
              if (len > 0) {
                exe_path[len] = '\0';
                bundle_id = g_strdup(exe_path);
              }
            }
          }
        }
      } else if (prop != nullptr) {
        XFree(prop);
      }
    }

    XCloseDisplay(display);
  }

  // Update cached last non-self app if we just saw a non-self window.
  if (window_pid > 0 && window_pid != self->self_pid) {
    if (self->cached_app_name != nullptr) {
      g_free(self->cached_app_name);
    }
    if (self->cached_bundle_id != nullptr) {
      g_free(self->cached_bundle_id);
    }
    if (self->cached_icon_png != nullptr) {
      g_free(self->cached_icon_png);
      self->cached_icon_png = nullptr;
      self->cached_icon_size = 0;
    }

    self->cached_app_name = app_name;
    self->cached_bundle_id = bundle_id;
    self->cached_icon_png = icon_png;
    self->cached_icon_size = icon_size;
    self->has_cached_app = TRUE;

    // Ownership moved to cache, avoid double free below.
    app_name = nullptr;
    bundle_id = nullptr;
    icon_png = nullptr;
    icon_size = 0;
  }

  const gchar* name_to_use = nullptr;
  const gchar* bundle_to_use = nullptr;
  const guchar* icon_to_use = nullptr;
  gsize icon_size_to_use = 0;

  if (self->has_cached_app) {
    name_to_use = self->cached_app_name;
    bundle_to_use = self->cached_bundle_id;
    icon_to_use = self->cached_icon_png;
    icon_size_to_use = self->cached_icon_size;
  } else {
    name_to_use = app_name;
    bundle_to_use = bundle_id;
    icon_to_use = icon_png;
    icon_size_to_use = icon_size;
  }

  if (name_to_use != nullptr) {
    fl_value_set_string(map, "name", fl_value_new_string(name_to_use));
  } else {
    fl_value_set_string(map, "name", fl_value_new_null());
  }

  if (bundle_to_use != nullptr) {
    fl_value_set_string(map, "bundleId", fl_value_new_string(bundle_to_use));
  } else {
    fl_value_set_string(map, "bundleId", fl_value_new_null());
  }

  if (icon_to_use != nullptr && icon_size_to_use > 0) {
    FlValue* icon_value =
        fl_value_new_uint8_list(icon_to_use, icon_size_to_use);
    fl_value_set_string(map, "icon", icon_value);
  } else {
    fl_value_set_string(map, "icon", fl_value_new_null());
  }

  g_free(app_name);
  g_free(bundle_id);
  g_free(icon_png);

  return map;
}

static gboolean advanced_clipboard_get_window_icon(Display* display,
                                                   Window window,
                                                   guchar** out_png,
                                                   gsize* out_size) {
  if (out_png == nullptr || out_size == nullptr || display == nullptr) {
    return FALSE;
  }

  *out_png = nullptr;
  *out_size = 0;

  Atom net_wm_icon = XInternAtom(display, "_NET_WM_ICON", True);
  if (net_wm_icon == None) {
    return FALSE;
  }

  Atom actual_type = None;
  int actual_format = 0;
  unsigned long nitems = 0;
  unsigned long bytes_after = 0;
  unsigned char* data = nullptr;

  if (XGetWindowProperty(display,
                         window,
                         net_wm_icon,
                         0,
                         LONG_MAX,
                         False,
                         AnyPropertyType,
                         &actual_type,
                         &actual_format,
                         &nitems,
                         &bytes_after,
                         &data) != Success ||
      data == nullptr || nitems < 3) {
    if (data != nullptr) {
      XFree(data);
    }
    return FALSE;
  }

  unsigned long* longs = reinterpret_cast<unsigned long*>(data);
  unsigned long* end = longs + nitems;
  unsigned long* ptr = longs;

  guint32* best_pixels = nullptr;
  int best_width = 0;
  int best_height = 0;

  while (ptr + 2 < end) {
    unsigned long width = ptr[0];
    unsigned long height = ptr[1];
    if (width == 0 || height == 0) {
      break;
    }

    unsigned long count = width * height;
    if (ptr + 2 + count > end) {
      break;
    }

    if (static_cast<int>(width * height) > best_width * best_height) {
      g_free(best_pixels);
      best_pixels = static_cast<guint32*>(
          g_malloc(sizeof(guint32) * count));
      for (unsigned long i = 0; i < count; ++i) {
        best_pixels[i] = static_cast<guint32>(ptr[2 + i]);
      }
      best_width = static_cast<int>(width);
      best_height = static_cast<int>(height);
    }

    ptr += 2 + count;
  }

  XFree(data);

  if (best_pixels == nullptr || best_width <= 0 || best_height <= 0) {
    g_free(best_pixels);
    return FALSE;
  }

  gsize pixel_count = static_cast<gsize>(best_width) *
                      static_cast<gsize>(best_height);
  guchar* rgba = static_cast<guchar*>(
      g_malloc(pixel_count * 4));

  for (gsize i = 0; i < pixel_count; ++i) {
    guint32 argb = best_pixels[i];
    guchar a = (argb >> 24) & 0xFF;
    guchar r = (argb >> 16) & 0xFF;
    guchar g = (argb >> 8) & 0xFF;
    guchar b = argb & 0xFF;

    rgba[i * 4 + 0] = r;
    rgba[i * 4 + 1] = g;
    rgba[i * 4 + 2] = b;
    rgba[i * 4 + 3] = a;
  }

  g_free(best_pixels);

  auto destroy_pixels = [](guchar* pixels, gpointer user_data) {
    g_free(pixels);
  };

  GdkPixbuf* pixbuf = gdk_pixbuf_new_from_data(
      rgba,
      GDK_COLORSPACE_RGB,
      TRUE,
      8,
      best_width,
      best_height,
      best_width * 4,
      destroy_pixels,
      nullptr);

  if (pixbuf == nullptr) {
    g_free(rgba);
    return FALSE;
  }

  gchar* buffer = nullptr;
  gsize size = 0;
  GError* error = nullptr;

  gboolean ok = gdk_pixbuf_save_to_buffer(
      pixbuf,
      &buffer,
      &size,
      "png",
      &error,
      nullptr);

  g_object_unref(pixbuf);

  if (!ok || buffer == nullptr || size == 0) {
    if (error != nullptr) {
      g_error_free(error);
    }
    g_free(buffer);
    return FALSE;
  }

  if (error != nullptr) {
    g_error_free(error);
  }

  *out_png = reinterpret_cast<guchar*>(buffer);
  *out_size = size;
  return TRUE;
}
