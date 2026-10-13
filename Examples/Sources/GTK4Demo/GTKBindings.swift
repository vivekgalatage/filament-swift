import Foundation

// MARK: - Core GTK 4 / GDK 4 / GLib / GObject C Bindings

@_silgen_name("gtk_init")
func gtk_init()

@_silgen_name("gtk_application_new")
func gtk_application_new(_ application_id: UnsafePointer<CChar>?, _ flags: Int32) -> OpaquePointer?

@_silgen_name("g_application_run")
func g_application_run(
    _ app: OpaquePointer?,
    _ argc: Int32,
    _ argv: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
) -> Int32

@_silgen_name("g_object_unref")
func g_object_unref(_ object: OpaquePointer?)

@_silgen_name("g_free")
func g_free(_ mem: UnsafeMutableRawPointer?)

@_silgen_name("gtk_application_window_new")
func gtk_application_window_new(_ app: OpaquePointer?) -> OpaquePointer?

@_silgen_name("gtk_window_set_title")
func gtk_window_set_title(_ window: OpaquePointer?, _ title: UnsafePointer<CChar>?)

@_silgen_name("gtk_window_set_default_size")
func gtk_window_set_default_size(_ window: OpaquePointer?, _ width: Int32, _ height: Int32)

@_silgen_name("gtk_window_present")
func gtk_window_present(_ window: OpaquePointer?)

@_silgen_name("gtk_box_new")
func gtk_box_new(_ orientation: Int32, _ spacing: Int32) -> OpaquePointer?

@_silgen_name("gtk_window_set_child")
func gtk_window_set_child(_ window: OpaquePointer?, _ child: OpaquePointer?)

@_silgen_name("gtk_header_bar_new")
func gtk_header_bar_new() -> OpaquePointer?

@_silgen_name("gtk_window_set_titlebar")
func gtk_window_set_titlebar(_ window: OpaquePointer?, _ titlebar: OpaquePointer?)

@_silgen_name("gtk_drawing_area_new")
func gtk_drawing_area_new() -> OpaquePointer?

@_silgen_name("gtk_button_new_with_label")
func gtk_button_new_with_label(_ label: UnsafePointer<CChar>?) -> OpaquePointer?

@_silgen_name("gtk_header_bar_pack_start")
func gtk_header_bar_pack_start(_ bar: OpaquePointer?, _ child: OpaquePointer?)

@_silgen_name("gtk_header_bar_pack_end")
func gtk_header_bar_pack_end(_ bar: OpaquePointer?, _ child: OpaquePointer?)

@_silgen_name("gtk_box_append")
func gtk_box_append(_ box: OpaquePointer?, _ child: OpaquePointer?)

@_silgen_name("gtk_widget_set_vexpand")
func gtk_widget_set_vexpand(_ widget: OpaquePointer?, _ expand: Int32)

@_silgen_name("gtk_widget_set_hexpand")
func gtk_widget_set_hexpand(_ widget: OpaquePointer?, _ expand: Int32)

@_silgen_name("gtk_widget_get_realized")
func gtk_widget_get_realized(_ widget: OpaquePointer?) -> Int32

@_silgen_name("gdk_display_get_default")
func gdk_display_get_default() -> OpaquePointer?

@_silgen_name("gdk_surface_get_width")
func gdk_surface_get_width(_ surface: OpaquePointer?) -> Int32

@_silgen_name("gdk_surface_get_height")
func gdk_surface_get_height(_ surface: OpaquePointer?) -> Int32

@_silgen_name("dlsym")
func dlsym(_ handle: UnsafeMutableRawPointer?, _ symbol: UnsafePointer<CChar>?) -> UnsafeMutableRawPointer?

@_silgen_name("gtk_widget_add_tick_callback")
func gtk_widget_add_tick_callback(
    _ widget: OpaquePointer?,
    _ callback: @convention(c) (OpaquePointer?, OpaquePointer?, UnsafeMutableRawPointer?) -> Int32,
    _ user_data: UnsafeMutableRawPointer?,
    _ destroy_notify: (@convention(c) (UnsafeMutableRawPointer?) -> Void)?
) -> UInt32

@discardableResult
@_silgen_name("g_signal_connect_data")
func g_signal_connect_data(
    _ instance: OpaquePointer?,
    _ detailed_signal: UnsafePointer<CChar>?,
    _ c_handler: @convention(c) () -> Void,
    _ data: UnsafeMutableRawPointer?,
    _ destroy_data: UnsafeMutableRawPointer?,
    _ connect_flags: Int32
) -> CUnsignedLong

// MARK: - Control Panel Widget Bindings

@_silgen_name("gtk_scrolled_window_new")
func gtk_scrolled_window_new() -> OpaquePointer?

@_silgen_name("gtk_scrolled_window_set_policy")
func gtk_scrolled_window_set_policy(_ scrolled: OpaquePointer?, _ hbar: Int32, _ vbar: Int32)

@_silgen_name("gtk_scrolled_window_set_child")
func gtk_scrolled_window_set_child(_ scrolled: OpaquePointer?, _ child: OpaquePointer?)

@_silgen_name("gtk_widget_set_size_request")
func gtk_widget_set_size_request(_ widget: OpaquePointer?, _ width: Int32, _ height: Int32)

@_silgen_name("gtk_label_new")
func gtk_label_new(_ str: UnsafePointer<CChar>?) -> OpaquePointer?

@_silgen_name("gtk_scale_new_with_range")
func gtk_scale_new_with_range(_ orientation: Int32, _ min: Double, _ max: Double, _ step: Double) -> OpaquePointer?

@_silgen_name("gtk_range_set_value")
func gtk_range_set_value(_ range: OpaquePointer?, _ value: Double)

@_silgen_name("gtk_range_get_value")
func gtk_range_get_value(_ range: OpaquePointer?) -> Double

@_silgen_name("gtk_scale_set_draw_value")
func gtk_scale_set_draw_value(_ scale: OpaquePointer?, _ draw: Int32)

@_silgen_name("gtk_check_button_new_with_label")
func gtk_check_button_new_with_label(_ label: UnsafePointer<CChar>?) -> OpaquePointer?

@_silgen_name("gtk_check_button_get_active")
func gtk_check_button_get_active(_ button: OpaquePointer?) -> Int32

@_silgen_name("gtk_check_button_set_active")
func gtk_check_button_set_active(_ button: OpaquePointer?, _ active: Int32)

@_silgen_name("gtk_drop_down_new_from_strings")
func gtk_drop_down_new_from_strings(_ strings: UnsafePointer<UnsafePointer<CChar>?>?) -> OpaquePointer?

@_silgen_name("gtk_drop_down_set_selected")
func gtk_drop_down_set_selected(_ dropdown: OpaquePointer?, _ index: UInt32)

@_silgen_name("gtk_drop_down_get_selected")
func gtk_drop_down_get_selected(_ dropdown: OpaquePointer?) -> UInt32

@_silgen_name("gtk_separator_new")
func gtk_separator_new(_ orientation: Int32) -> OpaquePointer?

// MARK: - Native File Chooser Bindings

@_silgen_name("gtk_file_chooser_native_new")
func gtk_file_chooser_native_new(
    _ title: UnsafePointer<CChar>?,
    _ parent: OpaquePointer?,
    _ action: Int32,
    _ accept_label: UnsafePointer<CChar>?,
    _ cancel_label: UnsafePointer<CChar>?
) -> OpaquePointer?

@_silgen_name("gtk_file_filter_new")
func gtk_file_filter_new() -> OpaquePointer?

@_silgen_name("gtk_file_filter_set_name")
func gtk_file_filter_set_name(_ filter: OpaquePointer?, _ name: UnsafePointer<CChar>?)

@_silgen_name("gtk_file_filter_add_pattern")
func gtk_file_filter_add_pattern(_ filter: OpaquePointer?, _ pattern: UnsafePointer<CChar>?)

@_silgen_name("gtk_file_chooser_add_filter")
func gtk_file_chooser_add_filter(_ chooser: OpaquePointer?, _ filter: OpaquePointer?)

@_silgen_name("gtk_native_dialog_show")
func gtk_native_dialog_show(_ dialog: OpaquePointer?)

@_silgen_name("gtk_native_dialog_destroy")
func gtk_native_dialog_destroy(_ dialog: OpaquePointer?)

@_silgen_name("gtk_file_chooser_get_file")
func gtk_file_chooser_get_file(_ chooser: OpaquePointer?) -> OpaquePointer?

// MARK: - Pointer Gesture & Scroll Event Controller Bindings

@_silgen_name("gtk_gesture_drag_new")
func gtk_gesture_drag_new() -> OpaquePointer?

@_silgen_name("gtk_gesture_single_set_button")
func gtk_gesture_single_set_button(_ gesture: OpaquePointer?, _ button: UInt32)

@_silgen_name("gtk_gesture_single_get_current_button")
func gtk_gesture_single_get_current_button(_ gesture: OpaquePointer?) -> UInt32

@_silgen_name("gtk_event_controller_get_current_event_state")
func gtk_event_controller_get_current_event_state(_ controller: OpaquePointer?) -> UInt32

@_silgen_name("gtk_event_controller_scroll_new")
func gtk_event_controller_scroll_new(_ flags: Int32) -> OpaquePointer?

@_silgen_name("gtk_widget_add_controller")
func gtk_widget_add_controller(_ widget: OpaquePointer?, _ controller: OpaquePointer?)

// MARK: - GTK Constants & Symbol Lookup

let GTK_ORIENTATION_HORIZONTAL: Int32 = 0
let GTK_ORIENTATION_VERTICAL: Int32 = 1
let GTK_POLICY_AUTOMATIC: Int32 = 1
let GTK_FILE_CHOOSER_ACTION_OPEN: Int32 = 0
let GTK_RESPONSE_ACCEPT: Int32 = -3
let GTK_EVENT_CONTROLLER_SCROLL_VERTICAL: Int32 = 1 << 0
let GDK_SHIFT_MASK: UInt32 = 1 << 0

/// Resolves a GTK/GDK/GIO entry point at runtime via `dlsym`.
func lookupSymbol<T>(_ name: String, as type: T.Type) -> T? {
    guard let symbol = name.withCString({ dlsym(nil, $0) }) else { return nil }
    return unsafeBitCast(symbol, to: T.self)
}
