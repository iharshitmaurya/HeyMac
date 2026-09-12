import Foundation
import CryptoKit

/// Wraps another `SymmetricKeyProviding` and caches the first successful result in
/// memory, so the wrapped provider (e.g. `KeychainKeyProvider`, which may prompt Touch
/// ID via a `.userPresence`-gated Keychain item) is consulted at most once per process
/// lifetime. Thread-safe: `SecureStore`/`VerificationPipeline` may be invoked from the
/// socket server's per-connection handling.
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
