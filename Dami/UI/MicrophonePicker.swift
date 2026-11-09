import SwiftUI

/// Chooses the microphone: the macOS default, or a specific device. Used in the menu and Settings.
struct MicrophonePicker: View {
    let label: String
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var devices = InputDevices.shared

    var body: some View {
        Picker(label, selection: selection) {
            Text(defaultTitle).tag(String?.none)
            Divider()
            ForEach(devices.choices(selected: settings.inputDeviceUID)) { device in
                Text(device.name).tag(String?.some(device.id))
            }
        }
        .pickerStyle(.menu)
    }

    /// A saved mic that's unplugged shows as the default, which is what records. The choice is kept,
    /// so plugging it back in returns to it.
    private var selection: Binding<String?> {
        Binding(
            get: { settings.inputDeviceUID.flatMap { devices.isConnected($0) ? $0 : nil } },
            set: { settings.inputDeviceUID = $0 }
        )
    }

    private var defaultTitle: String {
        devices.systemDefault.map { "System default (\($0.name))" } ?? "System default"
    }
}
