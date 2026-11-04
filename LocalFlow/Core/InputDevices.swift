import Combine
import CoreAudio
import Foundation

/// A microphone Core Audio knows about.
struct InputDevice: Identifiable, Hashable, Sendable {
    /// Core Audio's device UID. Stable across reconnects, unlike `audioID`.
    let id: String
    let audioID: AudioObjectID
    let name: String
    let transport: UInt32

    /// Software devices such as "Microsoft Teams Audio", and aggregates built from other devices.
    var isVirtual: Bool {
        [kAudioDeviceTransportTypeVirtual, kAudioDeviceTransportTypeAggregate, kAudioDeviceTransportTypeAutoAggregate]
            .contains(transport)
    }

    var isBluetooth: Bool {
        [kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE].contains(transport)
    }

    /// For the history record.
    var transportName: String {
        switch transport {
        case kAudioDeviceTransportTypeBuiltIn: "builtIn"
        case kAudioDeviceTransportTypeUSB: "usb"
        case kAudioDeviceTransportTypeAggregate, kAudioDeviceTransportTypeAutoAggregate: "aggregate"
        case kAudioDeviceTransportTypeVirtual: "virtual"
        default:
            if isBluetooth { "bluetooth" } else if isContinuity { "continuity" } else { "other" }
        }
    }

    var isContinuity: Bool {
        [kAudioDeviceTransportTypeContinuityCaptureWired, kAudioDeviceTransportTypeContinuityCaptureWireless]
            .contains(transport)
    }
}

/// Reads microphones from Core Audio. Callable from any thread.
enum CoreAudioDevices {
    static func inputDevices() -> [InputDevice] {
        var address = propertyAddress(kAudioHardwarePropertyDevices)
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap(device).filter { hasInputChannels($0.audioID) }
    }

    static func defaultInput() -> InputDevice? {
        var address = propertyAddress(kAudioHardwarePropertyDefaultInputDevice)
        var id = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id) == noErr,
              id != kAudioObjectUnknown else { return nil }
        return device(id)
    }

    static func isAlive(_ id: AudioObjectID) -> Bool {
        var address = propertyAddress(kAudioDevicePropertyDeviceIsAlive)
        var alive: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(id, &address, 0, nil, &size, &alive) == noErr && alive != 0
    }

    static func propertyAddress(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }

    private static func device(_ id: AudioObjectID) -> InputDevice? {
        guard let uid = string(id, kAudioDevicePropertyDeviceUID) else { return nil }
        var address = propertyAddress(kAudioDevicePropertyTransportType)
        var transport: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(id, &address, 0, nil, &size, &transport)
        return InputDevice(id: uid, audioID: id, name: string(id, kAudioObjectPropertyName) ?? "Microphone", transport: transport)
    }

    private static func string(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = propertyAddress(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }

    private static func hasInputChannels(_ id: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr, size > 0 else { return false }
        let storage = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { storage.deallocate() }
        let list = storage.bindMemory(to: AudioBufferList.self, capacity: 1)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, list) == noErr else { return false }
        return UnsafeMutableAudioBufferListPointer(list).contains { $0.mNumberChannels > 0 }
    }
}

/// The live list of microphones, for the pickers, plus which HUD notes have already been shown.
@MainActor
final class InputDevices: ObservableObject {
    static let shared = InputDevices()

    @Published private(set) var devices: [InputDevice] = []
    @Published private(set) var systemDefault: InputDevice?

    /// Wireless devices already warned about during their current connection.
    private var notedWireless: Set<String> = []
    /// The saved choice already reported as missing.
    private var notedMissing: String?
    /// The saved choice while it's been away, so its return can be announced once.
    private var awayChoice: String?

    private init() {
        refresh()
        for selector in [kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultInputDevice] {
            var address = CoreAudioDevices.propertyAddress(selector)
            AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main) { _, _ in
                MainActor.assumeIsolated { InputDevices.shared.refresh() }
            }
        }
    }

    /// What to offer in a picker: real microphones, plus a virtual one only if it's the current choice.
    func choices(selected: String?) -> [InputDevice] {
        devices.filter { !$0.isVirtual || $0.id == selected }
    }

    func isConnected(_ uid: String) -> Bool {
        devices.contains { $0.id == uid }
    }

    /// The one-time note for a recording that just started, if any.
    func note(for started: AudioRecorder.Started, chosen: String?) -> String? {
        if started.chosenMissing, notedMissing != chosen {
            notedMissing = chosen
            return "Selected mic not found · using \(started.device.name)"
        }
        if chosen != awayChoice {
            awayChoice = nil
        } else if !started.chosenMissing, chosen != nil {
            // Plugging a mic back in changes what records with no other sign of it.
            awayChoice = nil
            return "Using \(started.device.name)"
        }
        guard started.device.isBluetooth || started.device.isContinuity,
              notedWireless.insert(started.device.id).inserted else { return nil }
        return started.device.isContinuity ? "iPhone mic: first words may be cut" : "Bluetooth mic: first words may be cut"
    }

    private func refresh() {
        devices = CoreAudioDevices.inputDevices()
        systemDefault = CoreAudioDevices.defaultInput()
        let connected = Set(devices.map(\.id))
        notedWireless.formIntersection(connected)
        if let notedMissing, connected.contains(notedMissing) { self.notedMissing = nil }
        if let chosen = AppSettings.shared.inputDeviceUID, !connected.contains(chosen) { awayChoice = chosen }
    }
}
