import SwiftUI

/// Chooses the microphone: the macOS default, or a specific device. Used in the menu and Settings.
struct MicrophonePicker: View {
    let label: String
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var devices = InputDevices.shared

    var body: some View {
        Picker(label, selection: $settings.inputDeviceUID) {
            Text(defaultTitle).tag(String?.none)
            Divider()
            ForEach(devices.choices(selected: settings.inputDeviceUID)) { device in
                Text(device.name).tag(String?.some(device.id))
            }
            if let selected = settings.inputDeviceUID, !devices.isConnected(selected) {
                Text("Selected mic (not connected)").tag(String?.some(selected))
            }
        }
        .pickerStyle(.menu)
    }

    private var defaultTitle: String {
        devices.systemDefault.map { "System default (\($0.name))" } ?? "System default"
    }
}
