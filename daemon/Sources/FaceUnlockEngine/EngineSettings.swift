import Foundation

public enum MatchStrictness: String, CaseIterable, Sendable {
    case relaxed, normal, strict

    public var threshold: Float {
        switch self {
        case .relaxed: return 0.45
        case .normal: return 0.5
        case .strict: return 0.6
        }
    }

    public var title: String {
        switch self {
        case .relaxed: return "Relaxed"
        case .normal: return "Normal"
        case .strict: return "Strict"
        }
    }
}

/// Non-secret preferences. Secrets (enrollment, login password) stay in SecureStore.
public final class EngineSettings: @unchecked Sendable {
    private enum Key {
        static let setupComplete = "setupComplete"
        static let sudoEnabled = "sudoEnabled"
        static let lockScreenEnabled = "lockScreenEnabled"
        static let paused = "paused"
        static let lockScreenNeedsPassword = "lockScreenNeedsPassword"
        static let strictness = "matchStrictness"
        static let launchAtLogin = "launchAtLogin"
        static let all = [setupComplete, sudoEnabled, lockScreenEnabled, paused, lockScreenNeedsPassword, strictness, launchAtLogin]
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var setupComplete: Bool {
        get { defaults.bool(forKey: Key.setupComplete) }
        set { defaults.set(newValue, forKey: Key.setupComplete) }
    }

    public var sudoEnabled: Bool {
        get { defaults.bool(forKey: Key.sudoEnabled) }
        set { defaults.set(newValue, forKey: Key.sudoEnabled) }
    }

    public var lockScreenEnabled: Bool {
        get { defaults.bool(forKey: Key.lockScreenEnabled) }
        set { defaults.set(newValue, forKey: Key.lockScreenEnabled) }
    }

    public var paused: Bool {
        get { defaults.bool(forKey: Key.paused) }
        set { defaults.set(newValue, forKey: Key.paused) }
    }

    /// Set when a typed password left the screen locked; auto-typing stays off until the
    /// user saves the password again.
    public var lockScreenNeedsPassword: Bool {
        get { defaults.bool(forKey: Key.lockScreenNeedsPassword) }
        set { defaults.set(newValue, forKey: Key.lockScreenNeedsPassword) }
    }

    public var strictness: MatchStrictness {
        get { MatchStrictness(rawValue: defaults.string(forKey: Key.strictness) ?? "") ?? .normal }
        set { defaults.set(newValue.rawValue, forKey: Key.strictness) }
    }

    public var launchAtLogin: Bool {
        get { defaults.object(forKey: Key.launchAtLogin) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.launchAtLogin) }
    }

    public func resetAll() {
        Key.all.forEach { defaults.removeObject(forKey: $0) }
    }
}
