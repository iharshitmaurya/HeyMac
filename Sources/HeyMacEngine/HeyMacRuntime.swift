import Foundation
import HeyMacCore

/// Owns the loaded models, the camera and the encrypted store, and hands out the
/// pipelines/verifiers built from them.
///
/// Two stores on purpose: background verification must never wait on a Keychain dialog
/// nobody can see, while user-initiated actions (enroll, save password, Test Now) may
/// prompt once and have the user approve it.
public final class HeyMacRuntime: @unchecked Sendable {
    public static var defaultSupportDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/HeyMac", isDirectory: true)
    }

    public let supportDirectory: URL
    public let camera: CameraCapture
    /// Shared by every camera user, so only one verification or enrollment runs at a time.
    public let sessionLock = NSLock()
    public let interactiveStore: SecureStore
    public let backgroundStore: SecureStore

    private let interactiveKeys: KeychainKeyProvider
    private let interactiveCache: CachingKeyProvider
    private let backgroundCache: CachingKeyProvider
    private let embedder: FaceEmbedder
    private let classifier: AntiSpoofClassifier

    public init(supportDirectory: URL = HeyMacRuntime.defaultSupportDirectory) throws {
        self.supportDirectory = supportDirectory
        try FileManager.default.createDirectory(
            at: supportDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]
        )
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: supportDirectory.path)

        interactiveKeys = KeychainKeyProvider(account: NSUserName(), interactive: true)
        interactiveCache = CachingKeyProvider(wrapping: interactiveKeys)
        backgroundCache = CachingKeyProvider(wrapping: KeychainKeyProvider(account: NSUserName(), interactive: false))
        interactiveStore = SecureStore(keyProvider: interactiveCache, directory: supportDirectory)
        backgroundStore = SecureStore(keyProvider: backgroundCache, directory: supportDirectory)

        embedder = try FaceEmbedder()
        classifier = try AntiSpoofClassifier()
        camera = CameraCapture()
    }

    public func pipeline(interactive: Bool, strictness: MatchStrictness) -> VerificationPipeline {
        VerificationPipeline(
            embedder: embedder, classifier: classifier,
            store: interactive ? interactiveStore : backgroundStore,
            config: PipelineConfig(matchThreshold: strictness.threshold)
        )
    }

    public func verifier(interactive: Bool, strictness: MatchStrictness) -> FaceVerifier {
        FaceVerifier(camera: camera, pipeline: pipeline(interactive: interactive, strictness: strictness), sessionLock: sessionLock)
    }

    public func enroller() -> Enroller {
        Enroller(frames: camera, sampler: pipeline(interactive: true, strictness: .normal), sessionLock: sessionLock)
    }

    public var hasLoginPassword: Bool { fileExists(StoredItems.loginPassword) }

    public func saveLoginPassword(_ password: String) throws {
        try interactiveStore.save(Data(password.utf8), as: StoredItems.loginPassword)
    }

    /// Deletes the enrolled face, the stored password and the encryption key.
    public func removeAllData() throws {
        try removeFile(StoredItems.faceCentroid)
        try removeFile(StoredItems.loginPassword)
        try interactiveKeys.deleteKey()
        interactiveCache.clearCache()
        backgroundCache.clearCache()
    }

    private func fileExists(_ name: String) -> Bool {
        FileManager.default.fileExists(atPath: supportDirectory.appendingPathComponent(name).path)
    }

    private func removeFile(_ name: String) throws {
        let url = supportDirectory.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }
}
