import Foundation
import XCTest
@testable import WhisperHotkeyShell

final class LoginItemManagerTests: XCTestCase {
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
        let preferences = FakeLoginItemPreferenceStore()
        let manager = LoginItemManager(
            service: service,
            preferenceStore: preferences
        )

        XCTAssertEqual(try manager.enableAutomaticallyIfReady(false), .notRegistered)
        XCTAssertEqual(service.registerCount, 0)

        XCTAssertEqual(try manager.enableAutomaticallyIfReady(true), .enabled)
        XCTAssertEqual(service.registerCount, 1)
    }

    @MainActor
    func testFirstRegistrationTreatsNotFoundAsUnregistered() throws {
        let service = FakeLoginItemService(state: .notFound)
        let preferences = FakeLoginItemPreferenceStore()
        let manager = LoginItemManager(
            service: service,
            preferenceStore: preferences
        )

        XCTAssertEqual(try manager.enableExplicitly(), .enabled)
        XCTAssertEqual(service.registerCount, 1)
    }

    @MainActor
    func testUnregisterIsIdempotentAtManagerBoundary() throws {
        let service = FakeLoginItemService(state: .enabled)
        let preferences = FakeLoginItemPreferenceStore()
        let manager = LoginItemManager(
            service: service,
            preferenceStore: preferences
        )

        XCTAssertEqual(try manager.unregister(), .notRegistered)
        XCTAssertEqual(try manager.unregister(), .notRegistered)
        XCTAssertEqual(service.unregisterCount, 1)
        XCTAssertTrue(preferences.explicitlyDisabled)
    }

    @MainActor
    func testExplicitDisablePreventsLaterAutomaticRegistration() throws {
        let preferences = FakeLoginItemPreferenceStore()
        let enabledService = FakeLoginItemService(state: .enabled)
        let firstManager = LoginItemManager(
            service: enabledService,
            preferenceStore: preferences
        )

        XCTAssertEqual(try firstManager.disableExplicitly(), .notRegistered)
        XCTAssertTrue(preferences.explicitlyDisabled)

        let relaunchedService = FakeLoginItemService()
        let relaunchedManager = LoginItemManager(
            service: relaunchedService,
            preferenceStore: preferences
        )

        XCTAssertFalse(relaunchedManager.automaticRegistrationAllowed)
        XCTAssertEqual(
            try relaunchedManager.enableAutomaticallyIfReady(true),
            .notRegistered
        )
        XCTAssertTrue(preferences.explicitlyDisabled)
        XCTAssertEqual(relaunchedService.registerCount, 0)
    }

    @MainActor
    func testExplicitEnableClearsOptOutAndRegisters() throws {
        let preferences = FakeLoginItemPreferenceStore(explicitlyDisabled: true)
        let service = FakeLoginItemService()
        let manager = LoginItemManager(
            service: service,
            preferenceStore: preferences
        )

        XCTAssertEqual(try manager.enableExplicitly(), .enabled)
        XCTAssertTrue(manager.automaticRegistrationAllowed)
        XCTAssertFalse(preferences.explicitlyDisabled)
        XCTAssertEqual(service.registerCount, 1)
    }

    @MainActor
    func testUserDefaultsPreferencePersistsAcrossStoreInstances() throws {
        let suiteName = "local.whisperhotkey.login-item-tests.\(UUID().uuidString)"
        let firstDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        firstDefaults.removePersistentDomain(forName: suiteName)
        defer {
            firstDefaults.removePersistentDomain(forName: suiteName)
        }

        let firstStore = UserDefaultsLoginItemPreferenceStore(
            defaults: firstDefaults
        )
        firstStore.explicitlyDisabled = true

        let secondDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let secondStore = UserDefaultsLoginItemPreferenceStore(
            defaults: secondDefaults
        )
        XCTAssertTrue(secondStore.explicitlyDisabled)
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

@MainActor
private final class FakeLoginItemPreferenceStore: LoginItemPreferenceStoring {
    var explicitlyDisabled: Bool

    init(explicitlyDisabled: Bool = false) {
        self.explicitlyDisabled = explicitlyDisabled
    }
}
