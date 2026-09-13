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
}
