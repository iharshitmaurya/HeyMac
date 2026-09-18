import Foundation

public enum FaceAuthResult: Equatable, Sendable { case matched, noMatch, unavailable }
public enum SystemAuthResult: Equatable, Sendable { case success, cancelled, failed(String) }
public enum AuthMethod: Equatable, Sendable { case face, system }
public enum AuthOutcome: Equatable, Sendable { case unlocked(AuthMethod), cancelled, denied(String) }

public protocol FaceAuthSource: Sendable {
    func authenticate(timeout: TimeInterval) async -> FaceAuthResult
}

public protocol SystemAuthSource: Sendable {
    func authenticate(reason: String) async -> SystemAuthResult
}

/// One authentication attempt: face first, then Touch ID / the macOS password via the
/// system. `face` is nil when face unlock isn't set up or is paused. Cancelling the task
/// returns `.cancelled` without ever showing the system prompt.
public struct AuthCoordinator: Sendable {
    private let face: FaceAuthSource?
    private let system: SystemAuthSource
    private let faceTimeout: TimeInterval

    public init(face: FaceAuthSource?, system: SystemAuthSource, faceTimeout: TimeInterval = 3) {
        self.face = face
        self.system = system
        self.faceTimeout = faceTimeout
    }

    public func run(reason: String) async -> AuthOutcome {
        if Task.isCancelled { return .cancelled }
        if let face, await face.authenticate(timeout: faceTimeout) == .matched {
            return .unlocked(.face)
        }
        if Task.isCancelled { return .cancelled }
        switch await system.authenticate(reason: reason) {
        case .success: return .unlocked(.system)
        case .cancelled: return .cancelled
        case .failed(let message): return .denied(message)
        }
    }
}
