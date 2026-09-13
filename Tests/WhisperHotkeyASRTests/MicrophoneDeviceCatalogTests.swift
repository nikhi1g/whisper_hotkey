import CoreAudio
import XCTest
@testable import WhisperHotkeyASR

final class MicrophoneDeviceCatalogTests: XCTestCase {
    func testHidesCoreAudioGeneratedDefaultAggregate() {
        XCTAssertFalse(
            MicrophoneDeviceCatalog.shouldExposeDevice(
                named: "CADefaultDeviceAggregate-46794-0"
            )
        )
        XCTAssertTrue(
            MicrophoneDeviceCatalog.shouldExposeDevice(
                named: "Nikhil's Aggregate Device"
            )
        )
        XCTAssertTrue(
            MicrophoneDeviceCatalog.shouldExposeDevice(
                named: "Aeropods"
            )
        )
    }

    func testAutomaticUsesBuiltInInputForBluetoothDuplex() {
        XCTAssertTrue(
            MicrophoneDeviceCatalog.shouldUseBuiltInFallback(
                defaultInputName: "Aeropods",
                defaultInputTransport: kAudioDeviceTransportTypeBluetooth,
                defaultOutputTransport: kAudioDeviceTransportTypeBluetooth
            )
        )
        XCTAssertTrue(
            MicrophoneDeviceCatalog.shouldUseBuiltInFallback(
                defaultInputName: "CADefaultDeviceAggregate-46794-0",
                defaultInputTransport: kAudioDeviceTransportTypeAggregate,
                defaultOutputTransport: kAudioDeviceTransportTypeBluetooth
            )
        )
    }

    func testAutomaticPreservesIndependentAndNonBluetoothRoutes() {
        XCTAssertFalse(
            MicrophoneDeviceCatalog.shouldUseBuiltInFallback(
                defaultInputName: "Desk Microphone",
                defaultInputTransport: kAudioDeviceTransportTypeUSB,
                defaultOutputTransport: kAudioDeviceTransportTypeBluetooth
            )
        )
        XCTAssertFalse(
            MicrophoneDeviceCatalog.shouldUseBuiltInFallback(
                defaultInputName: "Aeropods",
                defaultInputTransport: kAudioDeviceTransportTypeBluetooth,
                defaultOutputTransport: kAudioDeviceTransportTypeBuiltIn
            )
        )
    }
}
