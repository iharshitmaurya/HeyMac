import ApplicationServices
import CoreGraphics
import Foundation
import HeyMacCore

/// Everything the unlocker needs from the system, injectable for tests.
public struct LockScreenEnvironment {
    public var isLocked: () -> Bool?
    public var displayIsAwake: () -> Bool
    public var accessibilityTrusted: () -> Bool
    public var loadPassword: () throws -> String
    public var wakeDisplay: () -> Void
    public var sleep: (TimeInterval) -> Void

    public init(
        isLocked: @escaping () -> Bool?, displayIsAwake: @escaping () -> Bool, accessibilityTrusted: @escaping () -> Bool,
        loadPassword: @escaping () throws -> String, wakeDisplay: @escaping () -> Void, sleep: @escaping (TimeInterval) -> Void
    ) {
        self.isLocked = isLocked
        self.displayIsAwake = displayIsAwake
        self.accessibilityTrusted = accessibilityTrusted
        self.loadPassword = loadPassword
        self.wakeDisplay = wakeDisplay
        self.sleep = sleep
    }

    public static func live(store: SecureStore) -> LockScreenEnvironment {
        LockScreenEnvironment(
            isLocked: { isScreenLocked() },
            displayIsAwake: { CGDisplayIsAsleep(CGMainDisplayID()) == 0 },
            accessibilityTrusted: { AXIsProcessTrusted() },
            loadPassword: {
                guard let text = String(data: try store.load(StoredItems.loginPassword), encoding: .utf8) else {
                    throw SecureStoreError.decryptionFailed
                }
                return text
            },
            wakeDisplay: {
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
                task.arguments = ["-u", "-t", "1"]
                try? task.run()
            },
            sleep: { Thread.sleep(forTimeInterval: $0) }
        )
    }
}

public enum LockScreenTick: Equatable {
    case notLocked
    case alreadyAttempted
    case blocked(String)
    case displayAsleep
    case noMatch
    case typingFailed(String)
    case unlocked
    case passwordRejected
}

/// While the screen is locked and the display is on, looks for the enrolled face and
/// types the stored password — at most once per lock episode. If the screen is still
/// locked afterwards the password is treated as wrong and auto-typing stops until the
/// user saves it again, so a stale password can't lock the account out.
public final class LockScreenUnlocker: @unchecked Sendable {
    static let unlockConfirmationDelay: TimeInterval = 5
    static let unlockPollInterval: TimeInterval = 0.15
    static let pollInterval: TimeInterval = 0.25

    private let matcher: FaceMatching
    private let typist: PasswordTyping
    private let settings: EngineSettings
    private let environment: LockScreenEnvironment
    private let onEvent: (EngineEvent) -> Void
    private let stateLock = NSLock()
    private var running = false
    private var stopRequested = false
    private var attemptedThisEpisode = false
    private var lastReportedProblem: String?

    public init(
        matcher: FaceMatching, typist: PasswordTyping, settings: EngineSettings,
        environment: LockScreenEnvironment, onEvent: @escaping (EngineEvent) -> Void
    ) {
        self.matcher = matcher
        self.typist = typist
        self.settings = settings
        self.environment = environment
        self.onEvent = onEvent
    }

    public func start() {
        let shouldStart = stateLock.withLock { () -> Bool in
            guard !running else { return false }
            running = true
            stopRequested = false
            return true
        }
        guard shouldStart else { return }
        Thread.detachNewThread { [self] in
            while !isStopRequested {
                tick()
                environment.sleep(Self.pollInterval)
            }
            stateLock.withLock { running = false }
        }
    }

    public func stop() {
        stateLock.withLock { stopRequested = true }
    }

    private var isStopRequested: Bool { stateLock.withLock { stopRequested } }

    @discardableResult
    func tick() -> LockScreenTick {
        guard environment.isLocked() == true else {
            stateLock.withLock {
                attemptedThisEpisode = false
                lastReportedProblem = nil
            }
            return .notLocked
        }
        if stateLock.withLock({ attemptedThisEpisode }) { return .alreadyAttempted }
        if case .refuse(let reason) = VerificationGate.lockScreen(settings, accessibilityTrusted: environment.accessibilityTrusted()) {
            // Paused / turned off are the user's choice, not problems worth reporting.
            return reason == VerificationGate.accessibilityMissing ? report(reason) : .blocked(reason)
        }
        guard environment.displayIsAwake() else { return .displayAsleep }

        let password: String
        do {
            password = try environment.loadPassword()
        } catch {
            return report("stored password unavailable (\(error))")
        }

        onEvent(.lockScreenScanning)
        let outcome = matcher.run(
            timeout: 30, requiredConsecutive: 2, waitForTurn: 0,
            keepGoing: { !self.isStopRequested && !self.settings.paused && self.environment.isLocked() == true && self.environment.displayIsAwake() }
        )
        guard outcome.matched else {
            onEvent(.lockScreenScanEnded)
            return outcome.failure.map { report($0) } ?? .noMatch
        }

        stateLock.withLock { attemptedThisEpisode = true }
        let watcher = ScreensaverWatcher(
            lockChecker: ClosureLockChecker(check: environment.isLocked), typist: typist, wakeDisplay: environment.wakeDisplay
        )
        do {
            try watcher.attemptUnlock(password: password)
        } catch {
            onEvent(.lockScreenScanEnded)
            return .typingFailed("\(error)")
        }

        // Poll rather than sleep-then-check-once: a correct password unlocks in well
        // under a second, and the HUD should appear the moment it does, not after a
        // flat wait. Still gives a wrong/stale password the full window before giving up.
        var elapsed: TimeInterval = 0
        while elapsed < Self.unlockConfirmationDelay {
            environment.sleep(Self.unlockPollInterval)
            elapsed += Self.unlockPollInterval
            if environment.isLocked() == false {
                onEvent(.lockScreenUnlocked(summary: outcome.summary))
                return .unlocked
            }
        }
        settings.lockScreenNeedsPassword = true
        onEvent(.lockScreenPasswordRejected)
        return .passwordRejected
    }

    private func report(_ problem: String) -> LockScreenTick {
        let isNew = stateLock.withLock { () -> Bool in
            defer { lastReportedProblem = problem }
            return lastReportedProblem != problem
        }
        if isNew { onEvent(.lockScreenProblem(problem)) }
        return .blocked(problem)
    }
}

struct ClosureLockChecker: LockStateChecking {
    let check: () -> Bool?
    func isLocked() -> Bool? { check() }
}
