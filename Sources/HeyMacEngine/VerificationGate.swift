import Foundation

public enum GateDecision: Equatable, Sendable {
    case allow
    case refuse(String)
}

/// Whether a verification may run at all, decided before the camera is touched.
public enum VerificationGate {
    public static let accessibilityMissing = "Accessibility permission missing"
    public static let passwordRejected = "stored password was rejected; save it again in Settings"

    public static func lockScreen(_ settings: EngineSettings, accessibilityTrusted: Bool) -> GateDecision {
        if !settings.setupComplete { return .refuse("setup not complete") }
        if settings.paused { return .refuse("paused") }
        if !settings.lockScreenEnabled { return .refuse("lock-screen face unlock is off") }
        if settings.lockScreenNeedsPassword { return .refuse(passwordRejected) }
        if !accessibilityTrusted { return .refuse(accessibilityMissing) }
        return .allow
    }
}
