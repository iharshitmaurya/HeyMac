import Foundation

public enum EngineEvent: Equatable, Sendable {
    case sudo(matched: Bool, summary: String)
    case lockScreenUnlocked(summary: String)
    case lockScreenPasswordRejected
    case lockScreenProblem(String)

    public var logText: String {
        switch self {
        case .sudo(_, let summary): return "sudo: \(summary)"
        case .lockScreenUnlocked(let summary): return "lock screen: unlocked (\(summary))"
        case .lockScreenPasswordRejected: return "lock screen: typed password was rejected; auto-typing disabled until it is saved again"
        case .lockScreenProblem(let reason): return "lock screen: \(reason)"
        }
    }
}

public enum StoredItems {
    public static let loginPassword = "login-password"
    public static let faceCentroid = "face-centroid"
}
