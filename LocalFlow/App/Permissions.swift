import AVFoundation
import AppKit
import ApplicationServices

/// The three macOS permissions LocalFlow needs:
/// - Microphone: record your voice.
/// - Input Monitoring: notice the hotkey while another app is focused.
/// - Accessibility: send ⌘V to paste into the focused app.
@MainActor
final class Permissions: ObservableObject {
    static let shared = Permissions()

    @Published private(set) var microphone = false
    @Published private(set) var accessibility = false
    @Published private(set) var inputMonitoring = false

    var allGranted: Bool { microphone && accessibility && inputMonitoring }

    private var timer: Timer?

    private init() {
        refresh()
        // macOS doesn't notify apps when permissions change in System Settings, so poll.
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            Task { @MainActor in Permissions.shared.refresh() }
        }
    }

    func refresh() {
        microphone = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        accessibility = AXIsProcessTrusted()
        inputMonitoring = CGPreflightListenEventAccess()
    }

    func requestMicrophone() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { _ in
                Task { @MainActor in self.refresh() }
            }
        default:
            openSettings("Privacy_Microphone")
        }
    }

    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(options) {
            openSettings("Privacy_Accessibility")
        }
    }

    func requestInputMonitoring() {
        if !CGRequestListenEventAccess() {
            openSettings("Privacy_ListenEvent")
        }
    }

    private func openSettings(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }
}
