import XCTest
@testable import WhisperHotkeySystem

final class SystemPlaceholderTests: XCTestCase {
    func testModuleLoads() {
        _ = WhisperHotkeySystemModule.self
    }
}
