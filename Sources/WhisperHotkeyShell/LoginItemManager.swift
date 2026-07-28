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
public final class LoginItemManager {
    private let service: any LoginItemService

    public convenience init() {
        self.init(service: MainAppLoginItemService())
    }

    public init(service: any LoginItemService) {
        self.service = service
    }

    public var status: LoginItemStatus {
        LoginItemStatusMapper.status(for: service.state)
    }

    @discardableResult
    public func register() throws -> LoginItemStatus {
        if status == .notRegistered {
            try service.register()
        }
        return status
    }

    @discardableResult
    public func unregister() throws -> LoginItemStatus {
        if status == .enabled || status == .requiresApproval {
            try service.unregister()
        }
        return status
    }

    @discardableResult
    public func enableAutomaticallyIfReady(_ setupIsReady: Bool) throws -> LoginItemStatus {
        guard setupIsReady else {
            return status
        }
        return try register()
    }

    public func openLoginItemsSettings() {
        service.openLoginItemsSettings()
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
