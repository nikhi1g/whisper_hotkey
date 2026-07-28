import XCTest
@testable import WhisperHotkeyShell

final class LoginItemStatusMapperTests: XCTestCase {
    func testMapsEveryServiceState() {
        XCTAssertEqual(LoginItemStatusMapper.status(for: .enabled), .enabled)
        XCTAssertEqual(LoginItemStatusMapper.status(for: .requiresApproval), .requiresApproval)
        XCTAssertEqual(LoginItemStatusMapper.status(for: .notRegistered), .notRegistered)
        XCTAssertEqual(LoginItemStatusMapper.status(for: .notFound), .notFound)
        XCTAssertEqual(LoginItemStatusMapper.status(for: .unknown), .unknown)
    }

    @MainActor
    func testAutomaticallyRegistersOnlyWhenSetupIsReady() throws {
        let service = FakeLoginItemService()
        let manager = LoginItemManager(service: service)

        XCTAssertEqual(try manager.enableAutomaticallyIfReady(false), .notRegistered)
        XCTAssertEqual(service.registerCount, 0)

        XCTAssertEqual(try manager.enableAutomaticallyIfReady(true), .enabled)
        XCTAssertEqual(service.registerCount, 1)
    }

    @MainActor
    func testUnregisterIsIdempotentAtManagerBoundary() throws {
        let service = FakeLoginItemService(state: .enabled)
        let manager = LoginItemManager(service: service)

        XCTAssertEqual(try manager.unregister(), .notRegistered)
        XCTAssertEqual(try manager.unregister(), .notRegistered)
        XCTAssertEqual(service.unregisterCount, 1)
    }
}

@MainActor
private final class FakeLoginItemService: LoginItemService {
    var state: LoginItemServiceState
    var registerCount = 0
    var unregisterCount = 0

    init(state: LoginItemServiceState = .notRegistered) {
        self.state = state
    }

    func register() throws {
        registerCount += 1
        state = .enabled
    }

    func unregister() throws {
        unregisterCount += 1
        state = .notRegistered
    }

    func openLoginItemsSettings() {}
}
