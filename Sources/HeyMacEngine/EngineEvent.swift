import Foundation

public enum EngineEvent: Equatable, Sendable {
    /// Fired once per lock episode, right as the camera turns on to look for a face —
    /// the earliest moment a "we're checking" indicator can honestly appear.
    case lockScreenScanning
    case lockScreenUnlocked(summary: String)
    case lockScreenPasswordRejected
    /// A scan that began with `lockScreenScanning` ended without an unlock result — the indicator must close.
    case lockScreenScanEnded
    case lockScreenProblem(String)

    public var logText: String {
        switch self {
        case .lockScreenScanning: return "lock screen: scanning"
        case .lockScreenUnlocked(let summary): return "lock screen: unlocked (\(summary))"
        case .lockScreenPasswordRejected: return "lock screen: typed password was rejected; auto-typing disabled until it is saved again"
        case .lockScreenScanEnded: return "lock screen: scan ended without unlocking"
        case .lockScreenProblem(let reason): return "lock screen: \(reason)"
        }
    }
}

public enum StoredItems {
    public static let loginPassword = "login-password"
    public static let faceCentroid = "face-centroid"
}
