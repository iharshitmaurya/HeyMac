import Foundation
import FaceUnlockCore

/// Runs the parts that work in the background: the socket the sudo PAM module talks to,
/// and the lock-screen watcher.
public final class EngineController: @unchecked Sendable {
    private let settings: EngineSettings
    private let socketPath: String
    private let log: AppLog
    private let makeMatcher: () throws -> FaceMatching
    private let lockScreenEnvironment: LockScreenEnvironment
    private let typist: PasswordTyping
    private let onEvent: (EngineEvent) -> Void
    private let stateLock = NSLock()
    private var server: SocketServer?
    private var unlocker: LockScreenUnlocker?

    public init(
        settings: EngineSettings, socketPath: String, log: AppLog = .shared,
        makeMatcher: @escaping () throws -> FaceMatching, lockScreenEnvironment: LockScreenEnvironment,
        typist: PasswordTyping = KeystrokeInjector(), onEvent: @escaping (EngineEvent) -> Void
    ) {
        self.settings = settings
        self.socketPath = socketPath
        self.log = log
        self.makeMatcher = makeMatcher
        self.lockScreenEnvironment = lockScreenEnvironment
        self.typist = typist
        self.onEvent = onEvent
    }

    public convenience init(
        runtime: FaceUnlockRuntime, settings: EngineSettings, log: AppLog = .shared,
        onEvent: @escaping (EngineEvent) -> Void
    ) {
        self.init(
            settings: settings, socketPath: runtime.socketPath, log: log,
            makeMatcher: { runtime.verifier(interactive: false, strictness: settings.strictness) },
            lockScreenEnvironment: .live(store: runtime.backgroundStore),
            onEvent: onEvent
        )
    }

    public var isRunning: Bool { stateLock.withLock { server != nil } }

    public func start() throws {
        stop()
        guard settings.setupComplete else {
            log.write("engine idle: setup is not complete")
            return
        }
        let matcher = try makeMatcher()
        let server = SocketServer(path: socketPath) { [weak self] message in
            self?.respond(to: message, matcher: matcher) ?? .fail
        }
        try server.start()
        let unlocker = LockScreenUnlocker(
            matcher: matcher, typist: typist, settings: settings,
            environment: lockScreenEnvironment, onEvent: { [weak self] event in self?.record(event) }
        )
        unlocker.start()
        stateLock.withLock {
            self.server = server
            self.unlocker = unlocker
        }
        log.write("engine started (strictness \(settings.strictness.rawValue))")
    }

    public func stop() {
        let (server, unlocker) = stateLock.withLock { () -> (SocketServer?, LockScreenUnlocker?) in
            let previous = (self.server, self.unlocker)
            self.server = nil
            self.unlocker = nil
            return previous
        }
        unlocker?.stop()
        server?.stop()
        if server != nil { log.write("engine stopped") }
    }

    func respond(to message: WireMessage, matcher: FaceMatching) -> WireMessage {
        switch message {
        case .verify, .verifyLock:
            if case .refuse(let reason) = VerificationGate.sudo(settings) {
                log.write("sudo request refused: \(reason)")
                return .fail
            }
            // PAM waits up to 10s: 1s to get the camera if the lock screen holds it, then a
            // 5s window covering camera start-up, exposure warm-up and matching.
            let outcome = matcher.run(timeout: 5, requiredConsecutive: 2, waitForTurn: 1, keepGoing: { true })
            record(.sudo(matched: outcome.matched, summary: outcome.summary))
            return outcome.matched ? .ok : .fail
        case .ok, .fail:
            return .fail
        }
    }

    private func record(_ event: EngineEvent) {
        log.write(event.logText)
        onEvent(event)
    }
}
