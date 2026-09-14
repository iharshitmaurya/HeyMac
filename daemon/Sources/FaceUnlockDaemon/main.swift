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

let args = CommandLine.arguments

// set-password and clear-password only touch `store` — keep them ahead of the
// (slow, model-resource-dependent) model loading below so they never pay that cost
// and never fail just because the model bundle happens to be missing.
if args.count > 1 && args[1] == "set-password" {
    guard let passwordCString = getpass("Enter your macOS login password (used only to type it in for you at the lock screen; never displayed or logged): ") else {
        print("Failed to read password.")
        exit(1)
    }
    let password = String(cString: passwordCString)
    guard !password.isEmpty else {
        print("Password cannot be empty.")
        exit(1)
    }
    guard let confirmCString = getpass("Confirm password: ") else {
        print("Failed to read password.")
        exit(1)
    }
    let confirmation = String(cString: confirmCString)
    guard password == confirmation else {
        print("Passwords did not match. Nothing was saved.")
        exit(1)
    }
    do {
        try store.save(Data(password.utf8), as: "login-password")
        print("Password saved.")
    } catch {
        print("Failed to save password: \(error)")
        exit(1)
    }
    exit(0)
}

if args.count > 1 && args[1] == "clear-password" {
    let url = supportDir.appendingPathComponent("login-password")
    guard FileManager.default.fileExists(atPath: url.path) else {
        print("No stored password found.")
        exit(0)
    }
    do {
        try FileManager.default.removeItem(at: url)
        print("Stored password removed.")
    } catch {
        print("Failed to remove stored password: \(error)")
        exit(1)
    }
    exit(0)
}

// Everything below this point (enroll, and daemon mode) needs the ML models.
guard let embedder = try? FaceEmbedder(), let classifier = try? AntiSpoofClassifier() else {
    FileHandle.standardError.write(Data("faceunlockd: failed to load models\n".utf8))
    exit(1)
}
let pipeline = VerificationPipeline(embedder: embedder, classifier: classifier, store: store)

// Warm the Touch-ID-gated key cache once now, while we're definitely running
// interactively with the session unlocked (a fresh `launchctl kickstart` or enroll
// run) — never during a lock episode, where a background LaunchAgent has no way to
// present a Touch ID prompt. CachingKeyProvider then reuses this cached key for every
// later call, including ones made from the screensaver tick while the screen is locked.
_ = try? keyProvider.fetchOrCreateKey()

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
    private var frame: (image: CGImage, capturedAt: Date)?
    private let maxAge: TimeInterval

    init(maxAge: TimeInterval = 2.0) {
        self.maxAge = maxAge
    }

    func update(_ image: CGImage) {
        lock.lock(); frame = (image, Date()); lock.unlock()
    }

    /// Returns the latest frame only if it's still fresh (captured within `maxAge`).
    /// A stale or missing frame (e.g. the camera stopped delivering frames because the
    /// display slept or the app lost camera access) is treated as "no frame" — callers
    /// must never act on a frame that could predate the person actually being present.
    func current() -> CGImage? {
        lock.lock(); defer { lock.unlock() }
        guard let frame, Date().timeIntervalSince(frame.capturedAt) <= maxAge else { return nil }
        return frame.image
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

struct LockStateAdapter: LockStateChecking {
    func isLocked() -> Bool? { isScreenLocked() }
}

let keystrokeInjector = KeystrokeInjector()
let screensaverWatcher = ScreensaverWatcher(
    lockChecker: LockStateAdapter(),
    typist: keystrokeInjector,
    wakeDisplay: {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        task.arguments = ["-u", "-t", "1"]
        try? task.run()
        task.waitUntilExit()
    }
)

// One-shot latch bounding unlock attempts to at most one per lock episode: reset when
// the screen transitions back to unlocked (the natural episode boundary), and set right
// before the one attempt this episode gets. This prevents unbounded retries against a
// wrong/stale stored password, and prevents synthetic keystrokes from ever interleaving
// with the legitimate user's own manual password entry after the first attempt.
var hasAttemptedThisLockEpisode = false

let screensaverTimer = Timer(timeInterval: 2.0, repeats: true) { _ in
    guard isScreenLocked() == true else {
        hasAttemptedThisLockEpisode = false
        return
    }
    guard !hasAttemptedThisLockEpisode else { return }
    // Check for a stored password before running any ML inference — cheap guard first,
    // so a screen that's locked with no password ever configured doesn't burn CPU on
    // face-embedding + liveness inference every 2 seconds for nothing.
    guard let passwordData = try? store.load("login-password"),
          let password = String(data: passwordData, encoding: .utf8) else { return }
    guard let frame = frameHolder.current() else { return }
    guard let matched = try? pipeline.verify(image: frame), matched else { return }
    hasAttemptedThisLockEpisode = true
    try? screensaverWatcher.attemptUnlock(password: password)
}
RunLoop.main.add(screensaverTimer, forMode: .common)

print("faceunlockd running, socket at \(socketPath)")
RunLoop.main.run()
