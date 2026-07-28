import AppKit
import ServiceManagement

public enum LoginItemStatus: String, Codable, Equatable, Sendable {
    case enabled
    case requiresApproval
    case notRegistered
    case notFound
    case unknown

    public var isEnabled: Bool {
        self == .enabled
    }
}

public enum LoginItemServiceState: Equatable, Sendable {
    case enabled
    case requiresApproval
    case notRegistered
    case notFound
    case unknown
}

public enum LoginItemStatusMapper {
    public static func status(for state: LoginItemServiceState) -> LoginItemStatus {
        switch state {
        case .enabled:
            .enabled
        case .requiresApproval:
            .requiresApproval
        case .notRegistered:
            .notRegistered
        case .notFound:
            .notFound
        case .unknown:
            .unknown
        }
    }
}

@MainActor
public protocol LoginItemService: AnyObject {
    var state: LoginItemServiceState { get }
    func register() throws
    func unregister() throws
    func openLoginItemsSettings()
}

@MainActor
public protocol LoginItemPreferenceStoring: AnyObject {
    var explicitlyDisabled: Bool { get set }
}

@MainActor
public final class UserDefaultsLoginItemPreferenceStore: LoginItemPreferenceStoring {
    private let defaults: UserDefaults
    private let key: String

    public init(
        defaults: UserDefaults = .standard,
        key: String = "loginItemExplicitlyDisabled"
    ) {
        self.defaults = defaults
        self.key = key
    }

    public var explicitlyDisabled: Bool {
        get { defaults.bool(forKey: key) }
        set { defaults.set(newValue, forKey: key) }
    }
}

@MainActor
public final class LoginItemManager {
    private let service: any LoginItemService
    private let preferenceStore: any LoginItemPreferenceStoring

    public convenience init() {
        self.init(
            service: MainAppLoginItemService(),
            preferenceStore: UserDefaultsLoginItemPreferenceStore()
        )
    }

    public convenience init(service: any LoginItemService) {
        self.init(
            service: service,
            preferenceStore: UserDefaultsLoginItemPreferenceStore()
        )
    }

    public init(
        service: any LoginItemService,
        preferenceStore: any LoginItemPreferenceStoring
    ) {
        self.service = service
        self.preferenceStore = preferenceStore
    }

    public var status: LoginItemStatus {
        LoginItemStatusMapper.status(for: service.state)
    }

    public var automaticRegistrationAllowed: Bool {
        !preferenceStore.explicitlyDisabled
    }

    @discardableResult
    public func register() throws -> LoginItemStatus {
        try enableExplicitly()
    }

    @discardableResult
    public func enableExplicitly() throws -> LoginItemStatus {
        preferenceStore.explicitlyDisabled = false
        return try registerIfNeeded()
    }

    @discardableResult
    public func unregister() throws -> LoginItemStatus {
        try disableExplicitly()
    }

    @discardableResult
    public func disableExplicitly() throws -> LoginItemStatus {
        preferenceStore.explicitlyDisabled = true
        return try unregisterIfNeeded()
    }

    @discardableResult
    public func enableAutomaticallyIfReady(_ setupIsReady: Bool) throws -> LoginItemStatus {
        guard setupIsReady, automaticRegistrationAllowed else {
            return status
        }
        return try registerIfNeeded()
    }

    public func openLoginItemsSettings() {
        service.openLoginItemsSettings()
    }

    private func registerIfNeeded() throws -> LoginItemStatus {
        if status == .notRegistered {
            try service.register()
        }
        return status
    }

    private func unregisterIfNeeded() throws -> LoginItemStatus {
        if status == .enabled || status == .requiresApproval {
            try service.unregister()
        }
        return status
    }
}

@MainActor
private final class MainAppLoginItemService: LoginItemService {
    private let service = SMAppService.mainApp

    var state: LoginItemServiceState {
        switch service.status {
        case .enabled:
            .enabled
        case .requiresApproval:
            .requiresApproval
        case .notRegistered:
            .notRegistered
        case .notFound:
            .notFound
        @unknown default:
            .unknown
        }
    }

    func register() throws {
        try service.register()
    }

    func unregister() throws {
        try service.unregister()
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
