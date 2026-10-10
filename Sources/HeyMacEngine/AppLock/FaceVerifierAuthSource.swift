import Foundation

private final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var isSet: Bool { lock.lock(); defer { lock.unlock() }; return value }
    func set() { lock.lock(); value = true; lock.unlock() }
}

/// Runs the blocking `FaceMatching` window off the main thread and maps its outcome.
public final class FaceVerifierAuthSource: FaceAuthSource, @unchecked Sendable {
    private let matcher: FaceMatching

    public init(matcher: FaceMatching) {
        self.matcher = matcher
    }

    public func authenticate(timeout: TimeInterval) async -> FaceAuthResult {
        let matcher = self.matcher
        let cancelled = CancelFlag()
        let outcome = await withTaskCancellationHandler {
            await Task.detached(priority: .userInitiated) {
                matcher.run(timeout: timeout, requiredConsecutive: 2, waitForTurn: 0.5,
                            keepGoing: { !cancelled.isSet })
            }.value
        } onCancel: {
            cancelled.set()
        }
        return Self.classify(outcome)
    }

    /// A failure message means the camera/keychain/enrollment wasn't usable at all; no
    /// message means the window ran and simply didn't see a live match.
    public static func classify(_ outcome: VerificationOutcome) -> FaceAuthResult {
        if outcome.matched { return .matched }
        return outcome.failure == nil ? .noMatch : .unavailable
    }
}
