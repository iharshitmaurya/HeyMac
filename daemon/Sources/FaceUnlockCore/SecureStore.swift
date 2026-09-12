import Foundation
import CryptoKit

public enum SecureStoreError: Error, Equatable {
    case encryptionFailed
    case decryptionFailed
    case notFound
}

public protocol SymmetricKeyProviding {
    func fetchOrCreateKey() throws -> SymmetricKey
}

public final class SecureStore {
    private let keyProvider: SymmetricKeyProviding
    private let directory: URL

    public init(keyProvider: SymmetricKeyProviding, directory: URL) {
        self.keyProvider = keyProvider
        self.directory = directory
        try? FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
    }

    public func save(_ data: Data, as name: String) throws {
        let key = try keyProvider.fetchOrCreateKey()
        guard let sealed = try? AES.GCM.seal(data, using: key), let combined = sealed.combined else {
            throw SecureStoreError.encryptionFailed
        }
        let url = directory.appendingPathComponent(name)
        // Write to a sibling temp file created with 0600 from the start, then
        // atomically rename it into place — this avoids a window where the
        // encrypted credential file exists at the process's default umask
        // permissions before being locked down.
        let tempURL = directory.appendingPathComponent(".\(name).tmp-\(UUID().uuidString)")
        guard FileManager.default.createFile(
            atPath: tempURL.path, contents: combined, attributes: [.posixPermissions: 0o600]
        ) else {
            throw SecureStoreError.encryptionFailed
        }
        do {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: tempURL)
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            throw SecureStoreError.encryptionFailed
        }
    }

    public func load(_ name: String) throws -> Data {
        let url = directory.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw SecureStoreError.notFound
        }
        let key = try keyProvider.fetchOrCreateKey()
        let combined = try Data(contentsOf: url)
        guard let sealedBox = try? AES.GCM.SealedBox(combined: combined),
              let plaintext = try? AES.GCM.open(sealedBox, using: key)
        else {
            throw SecureStoreError.decryptionFailed
        }
        return plaintext
    }
}
