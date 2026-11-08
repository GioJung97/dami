import AVFoundation
import AppKit
import ApplicationServices
import os

private let log = Logger(subsystem: "io.github.giojung97.dami", category: "permissions")

/// The macOS permissions Dami uses:
/// - Microphone: record your voice.
/// - Accessibility: notice the hotkey in any app, and send ⌘V to paste into the focused app.
/// - Input Monitoring: on the one Mac tested (macOS 15.3), Accessibility was enough for the hotkey, and this check turned true along
///   with it. Asked for only if the hotkey doesn't start, since other macOS versions may differ.
@MainActor
final class Permissions: ObservableObject {
    static let shared = Permissions()

    @Published private(set) var microphone = false
    @Published private(set) var accessibility = false
    @Published private(set) var inputMonitoring = false

    /// The two that are always asked for. Whether everything works also depends on the hotkey: `DictationController.permissionsReady`.
    var coreGranted: Bool { microphone && accessibility }

    private var timer: Timer?
    private var accessibilityRequested = false
    private var inputMonitoringRequested = false

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

    /// The first press shows macOS's own prompt, which also adds Dami to the list in System Settings and has a button to go there.
    /// macOS may not show it twice, so a later press opens System Settings directly.
    func requestAccessibility() {
        if accessibilityRequested {
            openSettings("Privacy_Accessibility")
        } else {
            accessibilityRequested = true
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }
    }

    /// Works the same way as `requestAccessibility`.
    func requestInputMonitoring() {
        if inputMonitoringRequested {
            openSettings("Privacy_ListenEvent")
        } else {
            inputMonitoringRequested = true
            _ = CGRequestListenEventAccess()
        }
    }

    /// macOS can hold a new permission back from an app until it restarts, and offers Quit & Reopen for that. This is for someone who
    /// answered Later. The new copy starts after a pause, so two copies never run at once.
    func quitAndReopen() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", Bundle.main.bundlePath]
        do {
            try process.run()
            NSApp.terminate(nil)
        } catch {
            log.error("Reopen failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func openSettings(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }
}
