import Foundation
import Security

/// Errors surfaced by the DeepSeek API key keychain helper.  Failures are
/// reported explicitly instead of being collapsed to a silent `nil`.
public enum ProcessorKeychainError: Error, Equatable, Sendable {
    case unexpectedStatus(OSStatus)
    case unreadableData
    case emptyKey
}

/// Generic-password access for the DeepSeek API key.
///
/// Fixed contract (see POST_PROCESSING_PLAN.md §2 and
/// `setup_deepseek_wh_hotkey.sh`):
///   service: `com.whisperhotkey.deepseek`
///   account: `api-key`
///   kind:    generic password
///
/// Read precedence: `DEEPSEEK_API_KEY` in the process environment first
/// (development override), then the keychain.  The key never lives in
/// UserDefaults.
public enum ProcessorKeychain {
    public static let service = "com.whisperhotkey.deepseek"
    public static let account = "api-key"

    private static let environmentKey = "DEEPSEEK_API_KEY"

    /// Returns the stored API key, or `nil` when no item exists.
    ///
    /// A non-empty `DEEPSEEK_API_KEY` environment value wins over the
    /// keychain; a blank or whitespace-only value falls through to it.
    public static func read() throws -> String? {
        if let override = ProcessInfo.processInfo.environment[environmentKey] {
            let trimmed = override.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data,
                  let value = String(data: data, encoding: .utf8)
            else {
                throw ProcessorKeychainError.unreadableData
            }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                throw ProcessorKeychainError.emptyKey
            }
            return trimmed
        case errSecItemNotFound:
            return nil
        default:
            throw ProcessorKeychainError.unexpectedStatus(status)
        }
    }

    /// Atomically overwrites any existing item with `apiKey`: the old item
    /// is deleted first, then the new one is added.
    public static func store(apiKey: String) throws {
        let value = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            throw ProcessorKeychainError.emptyKey
        }
        try delete()
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(value.utf8),
        ]
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw ProcessorKeychainError.unexpectedStatus(status)
        }
    }

    /// Removes the stored item, tolerating absence.
    public static func delete() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw ProcessorKeychainError.unexpectedStatus(status)
        }
    }
}
