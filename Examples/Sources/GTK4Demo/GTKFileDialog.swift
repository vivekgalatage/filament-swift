import Foundation

/// Presents a native GTK 4 file chooser dialog (`GtkFileChooserNative`) filtered to `.glb` files.
@MainActor
enum GTKFileDialog {
    private final class CallbackBox {
        let onSelect: @MainActor (URL) -> Void
        init(_ onSelect: @escaping @MainActor (URL) -> Void) {
            self.onSelect = onSelect
        }
    }

    static func present(parentWindow: OpaquePointer?, onSelect: @escaping @MainActor (URL) -> Void) {
        guard let dialog = gtk_file_chooser_native_new(
            "Select glTF Binary (.glb) Model",
            parentWindow,
            GTK_FILE_CHOOSER_ACTION_OPEN,
            "_Open",
            "_Cancel"
        ) else { return }

        if let filter = gtk_file_filter_new() {
            gtk_file_filter_set_name(filter, "glTF Binary (*.glb)")
            gtk_file_filter_add_pattern(filter, "*.glb")
            gtk_file_filter_add_pattern(filter, "*.GLB")
            gtk_file_chooser_add_filter(dialog, filter)
        }

        let boxPtr = Unmanaged.passRetained(CallbackBox(onSelect)).toOpaque()

        let responseCallback: @convention(c) (OpaquePointer?, Int32, UnsafeMutableRawPointer?) -> Void = { dlg, response, userData in
            defer {
                if let dlg {
                    gtk_native_dialog_destroy(dlg)
                    g_object_unref(dlg)
                }
                if let userData {
                    Unmanaged<CallbackBox>.fromOpaque(userData).release()
                }
            }
            guard response == GTK_RESPONSE_ACCEPT, let dlg, let userData else { return }
            guard let gfile = gtk_file_chooser_get_file(dlg) else { return }
            defer { g_object_unref(gfile) }

            let getPath = lookupSymbol(
                "g_file_get_path",
                as: (@convention(c) (OpaquePointer?) -> UnsafeMutablePointer<CChar>?).self
            )
            guard let cPath = getPath?(gfile) else { return }
            let path = String(cString: cPath)
            g_free(cPath)

            // Retain the box across the Task boundary before `defer` releases the C callback's retain.
            let retainedBox = Unmanaged<CallbackBox>.fromOpaque(userData).retain()
            Task { @MainActor in
                let box = retainedBox.takeRetainedValue()
                box.onSelect(URL(fileURLWithPath: path))
            }
        }

        g_signal_connect_data(
            dialog,
            "response",
            unsafeBitCast(responseCallback, to: (@convention(c) () -> Void).self),
            boxPtr,
            nil,
            0
        )
        gtk_native_dialog_show(dialog)
    }
}
