// Manual verification steps (not automated — needs real camera + Touch ID hardware):
// 1. Run: daemon/scripts/install-launchagent.sh
// 2. Grant Camera permission to faceunlockd when macOS prompts (first camera access).
// 3. Run: ~/Library/Application\ Support/faceunlock/bin/faceunlockd enroll
//    - Grant Touch ID when prompted (KeychainKeyProvider's first-run key creation).
//    - Look at the camera for the 5-frame capture.
//    - Expect "Enrollment saved."
// 4. Confirm the daemon is running: launchctl print gui/$(id -u)/com.faceunlock.daemon
// 5. From a second terminal, manually send a VERIFY_LOCK message to the socket
//    (e.g. with `nc -U ~/Library/Application\ Support/faceunlock/faceunlock.sock`,
//    type VERIFY_LOCK, press enter) while looking at the camera — expect OK.
// 6. Repeat step 5 with someone else's face, or no face in frame — expect FAIL.
// 7. Repeat step 5 holding a photo of your own face up to the camera — expect
//    FAIL (anti-spoof should reject it). This is the one test that actually
//    proves the liveness check works; there is no automated substitute for it.

import CoreGraphics
import Foundation
import FaceUnlockCore

let supportDir = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Application Support/faceunlock", isDirectory: true)
try? FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
// createDirectory(attributes:) is a no-op if the directory already existed (e.g. created
// by the install script's `mkdir -p` at the default umask), so enforce 0700 explicitly.
try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: supportDir.path)

let socketPath = supportDir.appendingPathComponent("faceunlock.sock").path

let keyProvider = CachingKeyProvider(wrapping: KeychainKeyProvider(account: NSUserName()))
let store = SecureStore(keyProvider: keyProvider, directory: supportDir)

guard let embedder = try? FaceEmbedder(), let classifier = try? AntiSpoofClassifier() else {
    FileHandle.standardError.write(Data("faceunlockd: failed to load models\n".utf8))
    exit(1)
}
let pipeline = VerificationPipeline(embedder: embedder, classifier: classifier, store: store)

let args = CommandLine.arguments

if args.count > 1 && args[1] == "enroll" {
    print("Look at the camera. Capturing 5 frames over the next few seconds...")
    var captured: [CGImage] = []
    let semaphore = DispatchSemaphore(value: 0)
    let camera = CameraCapture(onFrame: { image in
        guard captured.count < 5 else { return }
        captured.append(image)
        if captured.count == 5 { semaphore.signal() }
    })
    try camera.start()
    let waitResult = semaphore.wait(timeout: .now() + 15)
    camera.stop()
    guard waitResult == .success else {
        print("Couldn't capture enough frames within 15 seconds — check Camera permission in System Settings and that no other app is using the camera.")
        exit(1)
    }

    do {
        try pipeline.enroll(images: captured)
        print("Enrollment saved.")
    } catch {
        print("Enrollment failed: \(error)")
        exit(1)
    }
    exit(0)
}

// Daemon mode: hold the most recent camera frame, answer VERIFY/VERIFY_LOCK over the socket.
final class LatestFrameHolder {
    private let lock = NSLock()
    private var frame: CGImage?
    func update(_ image: CGImage) {
        lock.lock(); frame = image; lock.unlock()
    }
    func current() -> CGImage? {
        lock.lock(); defer { lock.unlock() }; return frame
    }
}

let frameHolder = LatestFrameHolder()
let camera = CameraCapture(onFrame: { frameHolder.update($0) })
try camera.start()

let server = SocketServer(path: socketPath, handler: { message in
    switch message {
    case .verify, .verifyLock:
        guard let frame = frameHolder.current() else { return .fail }
        let matched = (try? pipeline.verify(image: frame)) ?? false
        return matched ? .ok : .fail
    case .ok, .fail:
        return .fail
    }
})
try server.start()

print("faceunlockd running, socket at \(socketPath)")
RunLoop.main.run()
