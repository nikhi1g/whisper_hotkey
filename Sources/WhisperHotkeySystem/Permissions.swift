@preconcurrency import ApplicationServices
import CoreGraphics

public enum SystemPermissionState: String, Equatable, Sendable {
    case granted
    case notGranted
}

public struct SystemPermissionPreflight: Equatable, Sendable {
    public let accessibility: SystemPermissionState
    public let inputMonitoring: SystemPermissionState

    public init(
        accessibility: SystemPermissionState,
        inputMonitoring: SystemPermissionState
    ) {
        self.accessibility = accessibility
        self.inputMonitoring = inputMonitoring
    }
}

public enum SystemPermissionController {
    public static func preflight() -> SystemPermissionPreflight {
        SystemPermissionPreflight(
            accessibility: AXIsProcessTrusted() ? .granted : .notGranted,
            inputMonitoring: CGPreflightListenEventAccess() ? .granted : .notGranted
        )
    }

    /// Prompts asynchronously when Accessibility has not already been granted.
    /// The return value is the preflight state at the time of this call.
    @discardableResult
    public static func requestAccessibility() -> SystemPermissionState {
        let options = [
            "AXTrustedCheckOptionPrompt": true as CFBoolean,
        ] as CFDictionary
        return AXIsProcessTrustedWithOptions(options) ? .granted : .notGranted
    }

    /// Requests Input Monitoring and returns the system's immediate result.
    @discardableResult
    public static func requestInputMonitoring() -> SystemPermissionState {
        CGRequestListenEventAccess() ? .granted : .notGranted
    }
}
