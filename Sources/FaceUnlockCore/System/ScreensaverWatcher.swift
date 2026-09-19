import Foundation

public protocol LockStateChecking {
    func isLocked() -> Bool?
}

public protocol PasswordTyping {
    func typeAndReturn(_ text: String) throws
}

public enum ScreensaverWatcherError: Error, Equatable {
    case lockStateChangedBeforeTyping
    case lockStateUnknown
}

public final class ScreensaverWatcher {
    private let lockChecker: LockStateChecking
    private let typist: PasswordTyping
    private let wakeDisplay: () -> Void

    public init(lockChecker: LockStateChecking, typist: PasswordTyping, wakeDisplay: @escaping () -> Void = {}) {
        self.lockChecker = lockChecker
        self.typist = typist
        self.wakeDisplay = wakeDisplay
    }

    /// The caller must only invoke this after already confirming a live face match.
    /// This method's sole responsibility is the safety-critical re-check: the screen
    /// must be confirmed locked immediately before typing, both before and after
    /// waking the display, since the lock state can change at any point.
    public func attemptUnlock(password: String) throws {
        switch lockChecker.isLocked() {
        case .some(true):
            break
        case .some(false):
            throw ScreensaverWatcherError.lockStateChangedBeforeTyping
        case .none:
            throw ScreensaverWatcherError.lockStateUnknown
        }

        wakeDisplay()

        switch lockChecker.isLocked() {
        case .some(true):
            break
        case .some(false):
            throw ScreensaverWatcherError.lockStateChangedBeforeTyping
        case .none:
            throw ScreensaverWatcherError.lockStateUnknown
        }

        try typist.typeAndReturn(password)
    }
}
