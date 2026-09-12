import Foundation
import CryptoKit
import Security
import LocalAuthentication

// Manual verification (not automatable — requires real Touch ID hardware and a
// signed app context with Keychain access):
//   1. Build the daemon executable, run it once, call fetchOrCreateKey() — expect
//      a Touch ID prompt, then a key returned.
//   2. Call fetchOrCreateKey() again in the same run — expect no prompt (cached
//      by whatever caller holds the key in memory; KeychainKeyProvider itself
//      re-reads the Keychain each call, which itself may re-prompt depending on
//      SecAccessControl's context reuse — note actual behavior here once observed).
//   3. Kill and restart the daemon, call fetchOrCreateKey() — expect a fresh
//      Touch ID prompt (no in-memory cache survives a process restart).
//   4. Cancel the Touch ID prompt — expect fetchOrCreateKey() to throw, never to
//      return a key or hang.
public final class KeychainKeyProvider: SymmetricKeyProviding {
    private let account: String
    private let service = "com.faceunlock.sessionkey"

    public init(account: String) {
        self.account = account
    }

    public func fetchOrCreateKey() throws -> SymmetricKey {
        if let existing = try readKey() {
            return existing
        }
        let newKey = SymmetricKey(size: .bits256)
        try store(newKey)
        guard let readBack = try readKey() else {
            throw SecureStoreError.encryptionFailed
        }
        return readBack
    }

    private func readKey() throws -> SymmetricKey? {
        let context = LAContext()
        context.localizedReason = "Unlock your face-unlock credentials"
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecUseAuthenticationContext as String: context,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw SecureStoreError.decryptionFailed
        }
        return SymmetricKey(data: data)
    }

    private func store(_ key: SymmetricKey) throws {
        guard let access = SecAccessControlCreateWithFlags(
            nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, .userPresence, nil
        ) else {
            throw SecureStoreError.encryptionFailed
        }
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: key.withUnsafeBytes { Data($0) },
            kSecAttrAccessControl as String: access,
        ]
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw SecureStoreError.encryptionFailed
        }
    }
}
