#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#include <glib/gstdio.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include <cstdlib>
#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

namespace {

constexpr gint kDefaultWindowWidth = 1280;
constexpr gint kDefaultWindowHeight = 720;
constexpr gint kMinimumWindowWidth = 640;
constexpr gint kMinimumWindowHeight = 360;
constexpr const gchar* kWindowGeometryGroup = "window";

struct WindowGeometry {
  gint x = 0;
  gint y = 0;
  gint width = kDefaultWindowWidth;
  gint height = kDefaultWindowHeight;
  gboolean has_position = FALSE;
};

gchar* window_geometry_directory() {
  return g_build_filename(g_get_user_config_dir(), "mirushin", nullptr);
}

gchar* window_geometry_path() {
  return g_build_filename(g_get_user_config_dir(), "mirushin", "window.ini",
                          nullptr);
}

gchar* executable_directory() {
  g_autofree gchar* executable_path =
      g_file_read_link("/proc/self/exe", nullptr);
  if (executable_path == nullptr) {
    return nullptr;
  }
  return g_path_get_dirname(executable_path);
}

void set_window_icon(GtkWindow* window) {
  g_autofree gchar* executable_dir = executable_directory();
  if (executable_dir == nullptr) return;

  g_autofree gchar* icon_path =
      g_build_filename(executable_dir, "data", "logo.png", nullptr);
  if (!g_file_test(icon_path, G_FILE_TEST_EXISTS)) {
    return;
  }

  g_autoptr(GError) error = nullptr;
  gtk_window_set_icon_from_file(window, icon_path, &error);
}

void configure_quickjs_bridge_library() {
  g_autofree gchar* executable_dir = executable_directory();
  if (executable_dir == nullptr) {
    return;
  }

  const gchar* library_name = "libquickjs_c_bridge_plugin.so";
  g_autofree gchar* bundled_path =
      g_build_filename(executable_dir, "lib", library_name, nullptr);
  g_autofree gchar* debug_bundle_path =
      g_build_filename(executable_dir, "..", "bundle", "lib", library_name,
                       nullptr);
  g_autofree gchar* sibling_lib_path =
      g_build_filename(executable_dir, "..", "lib", library_name, nullptr);

  const gchar* selected_path = bundled_path;
  if (g_file_test(bundled_path, G_FILE_TEST_EXISTS)) {
    selected_path = bundled_path;
  } else if (g_file_test(debug_bundle_path, G_FILE_TEST_EXISTS)) {
    selected_path = debug_bundle_path;
  } else if (g_file_test(sibling_lib_path, G_FILE_TEST_EXISTS)) {
    selected_path = sibling_lib_path;
  }

  setenv("LIBQUICKJSC_PATH", selected_path, 1);
}

gboolean load_window_geometry(WindowGeometry* geometry) {
  g_autofree gchar* path = window_geometry_path();
  g_autoptr(GKeyFile) key_file = g_key_file_new();
  if (!g_key_file_load_from_file(key_file, path, G_KEY_FILE_NONE, nullptr)) {
    return FALSE;
  }

  gint width = g_key_file_get_integer(key_file, kWindowGeometryGroup, "width",
                                      nullptr);
  gint height = g_key_file_get_integer(key_file, kWindowGeometryGroup, "height",
                                       nullptr);
  if (width < kMinimumWindowWidth || height < kMinimumWindowHeight) {
    return FALSE;
  }

  geometry->width = width;
  geometry->height = height;
  if (g_key_file_has_key(key_file, kWindowGeometryGroup, "x", nullptr) &&
      g_key_file_has_key(key_file, kWindowGeometryGroup, "y", nullptr)) {
    geometry->x = g_key_file_get_integer(key_file, kWindowGeometryGroup, "x",
                                         nullptr);
    geometry->y = g_key_file_get_integer(key_file, kWindowGeometryGroup, "y",
                                         nullptr);
    geometry->has_position = TRUE;
  }

  return TRUE;
}

void save_window_geometry(GtkWindow* window) {
  gint width = 0;
  gint height = 0;
  gtk_window_get_size(window, &width, &height);
  if (width < kMinimumWindowWidth || height < kMinimumWindowHeight) {
    return;
  }

  gint x = 0;
  gint y = 0;
  gtk_window_get_position(window, &x, &y);

  g_autoptr(GKeyFile) key_file = g_key_file_new();
  g_key_file_set_integer(key_file, kWindowGeometryGroup, "x", x);
  g_key_file_set_integer(key_file, kWindowGeometryGroup, "y", y);
  g_key_file_set_integer(key_file, kWindowGeometryGroup, "width", width);
  g_key_file_set_integer(key_file, kWindowGeometryGroup, "height", height);

  gsize data_length = 0;
  g_autofree gchar* data = g_key_file_to_data(key_file, &data_length, nullptr);
  if (data == nullptr) {
    return;
  }

  g_autofree gchar* directory = window_geometry_directory();
  if (g_mkdir_with_parents(directory, 0700) != 0) {
    return;
  }

  g_autofree gchar* path = window_geometry_path();
  g_file_set_contents(path, data, static_cast<gssize>(data_length), nullptr);
}

gboolean window_configure_cb(GtkWidget* widget, GdkEventConfigure* event,
                             gpointer user_data) {
  (void)event;
  (void)user_data;
  save_window_geometry(GTK_WINDOW(widget));
  return FALSE;
}

gboolean window_delete_cb(GtkWidget* widget, GdkEvent* event,
                          gpointer user_data) {
  (void)event;
  (void)user_data;
  save_window_geometry(GTK_WINDOW(widget));
  return FALSE;
}

}  // namespace

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));
  set_window_icon(window);

  // Use a header bar when running in GNOME as this is the common style used
  // by applications and is the setup most users will be using (e.g. Ubuntu
  // desktop).
  // If running on X and not using GNOME then just use a traditional title bar
  // in case the window manager does more exotic layout, e.g. tiling.
  // If running on Wayland assume the header bar will work (may need changing
  // if future cases occur).
  gboolean use_header_bar = TRUE;
#ifdef GDK_WINDOWING_X11
  GdkScreen* screen = gtk_window_get_screen(window);
  if (GDK_IS_X11_SCREEN(screen)) {
    const gchar* wm_name = gdk_x11_screen_get_window_manager_name(screen);
    if (g_strcmp0(wm_name, "GNOME Shell") != 0) {
      use_header_bar = FALSE;
    }
  }
#endif
  if (use_header_bar) {
    GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_title(header_bar, "MiruShin");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "MiruShin");
  }

  WindowGeometry geometry;
  if (load_window_geometry(&geometry)) {
    gtk_window_set_default_size(window, geometry.width, geometry.height);
    if (geometry.has_position) {
      gtk_window_move(window, geometry.x, geometry.y);
    }
  } else {
    gtk_window_set_default_size(window, kDefaultWindowWidth,
                                kDefaultWindowHeight);
  }
  g_signal_connect(window, "configure-event", G_CALLBACK(window_configure_cb),
                   nullptr);
  g_signal_connect(window, "delete-event", G_CALLBACK(window_delete_cb),
                   nullptr);

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  configure_quickjs_bridge_library();

  FlView* view = fl_view_new(project);
  GdkRGBA background_color;
  // Background defaults to black, override it here if necessary, e.g. #00000000
  // for transparent.
  gdk_rgba_parse(&background_color, "#000000");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  // Show the window when Flutter renders.
  // Requires the view to be realized so we can start rendering.
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;

  return TRUE;
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application startup.

  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application shutdown.

  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {}

MyApplication* my_application_new() {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_NON_UNIQUE, nullptr));
}
