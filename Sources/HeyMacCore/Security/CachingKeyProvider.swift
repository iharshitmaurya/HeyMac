import Foundation
import CryptoKit

/// Caches the first successful key fetch in memory so the Keychain is consulted once per
/// process. Failures are not cached, so access granted later (e.g. "Always Allow" clicked
/// from a Test Now run) is picked up by the running engine. Thread-safe.
public final class CachingKeyProvider: SymmetricKeyProviding {
    private let wrapped: SymmetricKeyProviding
    private let lock = NSLock()
    private var cached: SymmetricKey?

    public init(wrapping provider: SymmetricKeyProviding) {
        self.wrapped = provider
    }

    /// Forgets the cached key, so the next fetch consults the Keychain again (used after
    /// the key is deleted, so a later enrollment can't be encrypted with a stale key).
    public func clearCache() {
        lock.lock()
        defer { lock.unlock() }
        cached = nil
    }

    public func fetchOrCreateKey() throws -> SymmetricKey {
        lock.lock()
        defer { lock.unlock() }
        if let cached { return cached }
        let key = try wrapped.fetchOrCreateKey()
        cached = key
        return key
    }
}
