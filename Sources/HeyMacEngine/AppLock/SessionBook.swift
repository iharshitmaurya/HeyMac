import Foundation

/// Which locked apps are currently unlocked. Time comes from an injected monotonic clock
/// (system uptime), so changing the wall clock can't extend a session.
public final class SessionBook: @unchecked Sendable {
    private struct Session {
        var policy: RelockPolicy
        var expiry: TimeInterval?
    }

    private let now: () -> TimeInterval
    private let lock = NSLock()
    private var sessions: [String: Session] = [:]

    public init(now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.now = now
    }

    public func unlock(_ bundleID: String, policy: RelockPolicy) {
        lock.lock(); defer { lock.unlock() }
        var expiry: TimeInterval?
        if case .afterMinutes(let minutes) = policy { expiry = now() + Double(minutes) * 60 }
        sessions[bundleID] = Session(policy: policy, expiry: expiry)
    }

    public func isUnlocked(_ bundleID: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard let session = sessions[bundleID] else { return false }
        if let expiry = session.expiry, now() >= expiry {
            sessions[bundleID] = nil
            return false
        }
        return true
    }

    public func focusLost(_ bundleID: String) {
        lock.lock(); defer { lock.unlock() }
        guard var session = sessions[bundleID] else { return }
        switch session.policy {
        case .everyTime:
            sessions[bundleID] = nil
        case .afterFocusLossMinutes(let minutes):
            session.expiry = now() + Double(minutes) * 60
            sessions[bundleID] = session
        case .afterMinutes:
            break
        }
    }

    public func focusGained(_ bundleID: String) {
        lock.lock(); defer { lock.unlock() }
        guard var session = sessions[bundleID], case .afterFocusLossMinutes = session.policy else { return }
        if let expiry = session.expiry, now() >= expiry {
            sessions[bundleID] = nil
        } else {
            session.expiry = nil
            sessions[bundleID] = session
        }
    }

    public func revoke(_ bundleID: String) {
        lock.lock(); defer { lock.unlock() }
        sessions[bundleID] = nil
    }

    public func revokeAll() {
        lock.lock(); defer { lock.unlock() }
        sessions.removeAll()
    }
}
