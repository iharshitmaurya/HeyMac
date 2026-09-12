import Testing
import Foundation
import CryptoKit
@testable import FaceUnlockCore

final class FakeKeyProvider: SymmetricKeyProviding {
    let key: SymmetricKey
    init(key: SymmetricKey = SymmetricKey(size: .bits256)) { self.key = key }
    func fetchOrCreateKey() throws -> SymmetricKey { key }
}

func makeTempDirectory() -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

@Test func savedDataCanBeLoadedBack() throws {
    let store = SecureStore(keyProvider: FakeKeyProvider(), directory: makeTempDirectory())
    let original = Data("hello face unlock".utf8)
    try store.save(original, as: "test-item")
    let loaded = try store.load("test-item")
    #expect(loaded == original)
}

@Test func loadingMissingItemThrowsNotFound() throws {
    let store = SecureStore(keyProvider: FakeKeyProvider(), directory: makeTempDirectory())
    #expect(throws: SecureStoreError.notFound) {
        _ = try store.load("does-not-exist")
    }
}

@Test func dataEncryptedWithOneKeyCannotBeReadWithAnother() throws {
    let dir = makeTempDirectory()
    let writer = SecureStore(keyProvider: FakeKeyProvider(), directory: dir)
    try writer.save(Data("secret".utf8), as: "test-item")

    let reader = SecureStore(keyProvider: FakeKeyProvider(), directory: dir)
    #expect(throws: SecureStoreError.decryptionFailed) {
        _ = try reader.load("test-item")
    }
}

@Test func storedFileIsNotWorldReadable() throws {
    let dir = makeTempDirectory()
    let store = SecureStore(keyProvider: FakeKeyProvider(), directory: dir)
    try store.save(Data("secret".utf8), as: "test-item")
    let attrs = try FileManager.default.attributesOfItem(atPath: dir.appendingPathComponent("test-item").path)
    let permissions = attrs[.posixPermissions] as! NSNumber
    #expect(permissions.intValue == 0o600)
}

@Test func keychainKeyProviderIsConstructible() {
    _ = KeychainKeyProvider(account: "test-account-\(UUID().uuidString)")
}

// MARK: - Finding 2: CachingKeyProvider must call the wrapped provider at most once

final class CountingKeyProvider: SymmetricKeyProviding {
    private(set) var callCount = 0
    let key = SymmetricKey(size: .bits256)
    func fetchOrCreateKey() throws -> SymmetricKey {
        callCount += 1
        return key
    }
}

@Test func cachingKeyProviderCallsWrappedProviderAtMostOnce() throws {
    let inner = CountingKeyProvider()
    let caching = CachingKeyProvider(wrapping: inner)

    let first = try caching.fetchOrCreateKey()
    let second = try caching.fetchOrCreateKey()
    let third = try caching.fetchOrCreateKey()

    #expect(inner.callCount == 1)
    #expect(first == second)
    #expect(second == third)
}
