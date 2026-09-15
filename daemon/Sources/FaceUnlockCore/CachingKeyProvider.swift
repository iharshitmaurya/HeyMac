import Foundation
import CryptoKit

/// Caches the first successful key fetch in memory so the Keychain is consulted once per
/// process. Failures are not cached, so access granted later (e.g. "Always Allow" clicked
/// from a CLI run) is picked up by a running daemon. Thread-safe.
public final class CachingKeyProvider: SymmetricKeyProviding {
    private let wrapped: SymmetricKeyProviding
    private let lock = NSLock()
    private var cached: SymmetricKey?

    public init(wrapping provider: SymmetricKeyProviding) {
        self.wrapped = provider
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
