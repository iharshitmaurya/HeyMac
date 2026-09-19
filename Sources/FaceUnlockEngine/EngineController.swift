import Foundation
import FaceUnlockCore

/// Runs the background lock-screen watcher.
public final class EngineController: @unchecked Sendable {
    private let settings: EngineSettings
    private let log: AppLog
    private let makeMatcher: () throws -> FaceMatching
    private let lockScreenEnvironment: LockScreenEnvironment
    private let typist: PasswordTyping
    private let onEvent: (EngineEvent) -> Void
    private let stateLock = NSLock()
    private var unlocker: LockScreenUnlocker?

    public init(
        settings: EngineSettings, log: AppLog = .shared,
        makeMatcher: @escaping () throws -> FaceMatching, lockScreenEnvironment: LockScreenEnvironment,
        typist: PasswordTyping = KeystrokeInjector(), onEvent: @escaping (EngineEvent) -> Void
    ) {
        self.settings = settings
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
            settings: settings, log: log,
            makeMatcher: { runtime.verifier(interactive: false, strictness: settings.strictness) },
            lockScreenEnvironment: .live(store: runtime.backgroundStore),
            onEvent: onEvent
        )
    }

    public var isRunning: Bool { stateLock.withLock { unlocker != nil } }

    public func start() throws {
        stop()
        guard settings.setupComplete else {
            log.write("engine idle: setup is not complete")
            return
        }
        let matcher = try makeMatcher()
        let unlocker = LockScreenUnlocker(
            matcher: matcher, typist: typist, settings: settings,
            environment: lockScreenEnvironment, onEvent: { [weak self] event in self?.record(event) }
        )
        unlocker.start()
        stateLock.withLock { self.unlocker = unlocker }
        log.write("engine started (strictness \(settings.strictness.rawValue))")
    }

    public func stop() {
        let unlocker = stateLock.withLock { () -> LockScreenUnlocker? in
            defer { self.unlocker = nil }
            return self.unlocker
        }
        unlocker?.stop()
        if unlocker != nil { log.write("engine stopped") }
    }

    private func record(_ event: EngineEvent) {
        log.write(event.logText)
        onEvent(event)
    }
}
