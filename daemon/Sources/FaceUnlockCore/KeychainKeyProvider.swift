import CryptoKit
import Foundation
import Security

public enum KeychainKeyProviderError: Error, Equatable {
    /// The item exists but reading it needs user approval (typically the Keychain
    /// "allow access" dialog after the binary was rebuilt and its code signature changed).
    case interactionRequired(OSStatus)
    case notFound
    case readFailed(OSStatus)
    case storeFailed(OSStatus)
}

/// Holds the AES key that encrypts the enrolled face and the stored login password, as a
/// generic password in the login keychain. The keychain's per-app ACL keeps other apps
/// from reading it silently.
///
/// `interactive: false` is for the background daemon: it never shows a dialog (a LaunchAgent
/// blocked on an unseen prompt stops answering sudo and the lock screen) and never creates
/// a key (a fresh key would silently orphan the existing encrypted enrollment). Interactive
/// CLI commands (enroll, set-password, verify) may prompt; choosing "Always Allow" there
/// authorizes this binary for the daemon too, since both run the same executable.
public final class KeychainKeyProvider: SymmetricKeyProviding {
    private let account: String
    private let interactive: Bool
    private let service = "com.faceunlock.sessionkey"

    public init(account: String, interactive: Bool) {
        self.account = account
        self.interactive = interactive
    }

    public func fetchOrCreateKey() throws -> SymmetricKey {
        if let existing = try readKey() { return existing }
        guard interactive else { throw KeychainKeyProviderError.notFound }
        let key = SymmetricKey(size: .bits256)
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrLabel as String: "faceunlock encryption key",
            kSecValueData as String: key.withUnsafeBytes { Data($0) },
        ]
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainKeyProviderError.storeFailed(status) }
        return key
    }

    /// Removes the stored key. Data encrypted with it becomes unreadable, so this is only
    /// for "remove my face data".
    public func deleteKey() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainKeyProviderError.storeFailed(status)
        }
    }

    private func readKey() throws -> SymmetricKey? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        if !interactive {
            query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
        }
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data, data.count == 32 else { throw KeychainKeyProviderError.readFailed(status) }
            return SymmetricKey(data: data)
        case errSecItemNotFound:
            return nil
        case errSecInteractionNotAllowed, errSecAuthFailed, errSecUserCanceled:
            throw KeychainKeyProviderError.interactionRequired(status)
        default:
            throw KeychainKeyProviderError.readFailed(status)
        }
    }
}
