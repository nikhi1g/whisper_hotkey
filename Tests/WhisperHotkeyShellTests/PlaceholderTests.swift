import XCTest
@testable import WhisperHotkeyShell

final class ShellPlaceholderTests: XCTestCase {
    func testModuleLoads() {
        _ = WhisperHotkeyShellModule.self
    }
}
