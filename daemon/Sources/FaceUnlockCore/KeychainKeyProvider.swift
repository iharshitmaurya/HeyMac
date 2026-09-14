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
        try authenticate()
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

    // Biometric gating is done explicitly here rather than via SecAccessControl's
    // .userPresence flag: that flag requires a keychain-access-groups entitlement
    // tied to a real Team ID, which an ad-hoc-signed CLI binary (no paid/free Apple
    // Developer identity) cannot obtain — it fails every access with
    // errSecMissingEntitlement (-34018) regardless of code signing. Evaluating the
    // policy ourselves gives the same "must prove device ownership" property without
    // requiring any entitlement.
    private func authenticate() throws {
        let context = LAContext()
        var evalError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &evalError) else {
            throw SecureStoreError.encryptionFailed
        }
        let semaphore = DispatchSemaphore(value: 0)
        var success = false
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock your face-unlock credentials") { result, _ in
            success = result
            semaphore.signal()
        }
        semaphore.wait()
        guard success else {
            throw SecureStoreError.encryptionFailed
        }
    }

    private func readKey() throws -> SymmetricKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            FileHandle.standardError.write(Data("readKey failed, OSStatus \(status): \(SecCopyErrorMessageString(status, nil) ?? "unknown" as CFString)\n".utf8))
            throw SecureStoreError.decryptionFailed
        }
        return SymmetricKey(data: data)
    }

    private func store(_ key: SymmetricKey) throws {
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: key.withUnsafeBytes { Data($0) },
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            FileHandle.standardError.write(Data("store failed, OSStatus \(status): \(SecCopyErrorMessageString(status, nil) ?? "unknown" as CFString)\n".utf8))
            throw SecureStoreError.encryptionFailed
        }
    }
}
