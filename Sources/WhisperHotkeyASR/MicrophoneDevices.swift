import AudioToolbox
import AVFoundation
import CoreAudio
import Foundation
import WhisperHotkeyCore

public enum MicrophoneDeviceError: Error, Equatable {
    case unavailable(String)
    case queryFailed(OSStatus)
    case routingFailed(OSStatus)
}

public struct MicrophoneDeviceCatalog: Sendable {
    private struct ResolvedDevice {
        let id: AudioDeviceID
        let device: MicrophoneDevice
    }

    public init() {}

    public func availableDevices() throws -> [MicrophoneDevice] {
        let defaultID = try defaultInputDeviceID()
        return try resolvedInputDevices(defaultID: defaultID)
            .map(\.device)
            .sorted {
                let comparison = $0.name.localizedCaseInsensitiveCompare($1.name)
                return comparison == .orderedSame
                    ? $0.uid < $1.uid
                    : comparison == .orderedAscending
            }
    }

    public func effectiveDevice(
        for selection: MicrophoneSelection
    ) throws -> MicrophoneDevice {
        let defaultID = try defaultInputDeviceID()
        let devices = try resolvedInputDevices(defaultID: defaultID)
        if let uid = selection.deviceUID {
            guard let match = devices.first(where: { $0.device.uid == uid }) else {
                throw MicrophoneDeviceError.unavailable(
                    selection.displayName ?? uid
                )
            }
            return match.device
        }
        guard let match = devices.first(where: { $0.id == defaultID }) else {
            throw MicrophoneDeviceError.unavailable("System default microphone")
        }
        return match.device
    }

    func apply(
        _ selection: MicrophoneSelection,
        to engine: AVAudioEngine,
        preserveCurrentRoute: Bool = false
    ) throws -> MicrophoneDevice {
        let defaultID = try defaultInputDeviceID()
        let devices = try resolvedInputDevices(defaultID: defaultID)
        let resolved: ResolvedDevice?
        if let uid = selection.deviceUID {
            resolved = devices.first(where: { $0.device.uid == uid })
        } else {
            resolved = devices.first(where: { $0.id == defaultID })
        }
        guard let resolved else {
            throw MicrophoneDeviceError.unavailable(
                selection.displayName
                    ?? (selection.isAutomatic
                        ? "System default microphone"
                        : selection.deviceUID ?? "Selected microphone")
            )
        }
        guard let audioUnit = engine.inputNode.audioUnit else {
            throw MicrophoneDeviceError.routingFailed(kAudio_ParamError)
        }
        if preserveCurrentRoute {
            var currentDeviceID = AudioDeviceID(kAudioObjectUnknown)
            var size = UInt32(MemoryLayout<AudioDeviceID>.size)
            let status = AudioUnitGetProperty(
                audioUnit, kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global, 0, &currentDeviceID, &size
            )
            if status == noErr, currentDeviceID == resolved.id {
                return resolved.device
            }
        }
        var deviceID = resolved.id
        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &deviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        guard status == noErr else {
            throw MicrophoneDeviceError.routingFailed(status)
        }
        return resolved.device
    }

    private func resolvedInputDevices(
        defaultID: AudioDeviceID
    ) throws -> [ResolvedDevice] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size
        )
        guard status == noErr else {
            throw MicrophoneDeviceError.queryFailed(status)
        }
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &ids
        )
        guard status == noErr else {
            throw MicrophoneDeviceError.queryFailed(status)
        }
        return try ids.compactMap { id in
            guard try hasInputStreams(id) else { return nil }
            let name = try stringProperty(
                id,
                selector: kAudioObjectPropertyName
            )
            guard Self.shouldExposeDevice(named: name) else { return nil }
            return ResolvedDevice(
                id: id,
                device: MicrophoneDevice(
                    uid: try stringProperty(
                        id,
                        selector: kAudioDevicePropertyDeviceUID
                    ),
                    name: name,
                    isSystemDefault: id == defaultID
                )
            )
        }
    }

    static func shouldExposeDevice(named name: String) -> Bool {
        !name.hasPrefix("CADefaultDeviceAggregate-")
    }

    private func defaultInputDeviceID() throws -> AudioDeviceID {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &id
        )
        guard status == noErr, id != kAudioObjectUnknown else {
            throw MicrophoneDeviceError.queryFailed(status)
        }
        return id
    }

    private func hasInputStreams(_ id: AudioDeviceID) throws -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(
            id,
            &address,
            0,
            nil,
            &size
        )
        guard status == noErr else {
            throw MicrophoneDeviceError.queryFailed(status)
        }
        return size >= MemoryLayout<AudioStreamID>.size
    }

    private func stringProperty(
        _ id: AudioDeviceID,
        selector: AudioObjectPropertySelector
    ) throws -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(
                id,
                &address,
                0,
                nil,
                &size,
                pointer
            )
        }
        guard status == noErr else {
            throw MicrophoneDeviceError.queryFailed(status)
        }
        return value as String
    }
}
