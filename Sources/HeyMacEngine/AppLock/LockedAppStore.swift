import Foundation

public enum PrivacyLevel: String, Codable, Equatable, Sendable, CaseIterable {
    case none = "Low Privacy"
    case normal = "Standard Privacy"
    case high = "High Privacy"
}

public enum RelockPolicy: Codable, Equatable, Sendable {
    /// Locked again as soon as the app loses focus.
    case everyTime
    /// Locked N minutes after unlocking, regardless of focus.
    case afterMinutes(Int)
    /// Locked N minutes after the app loses focus; returning sooner keeps it unlocked.
    case afterFocusLossMinutes(Int)
}

public struct LockedApp: Codable, Equatable, Sendable, Identifiable {
    public var bundleID: String
    public var name: String
    public var policy: RelockPolicy
    public var id: String { bundleID }
}

/// Which apps are locked, and their relock policy. No secrets — UserDefaults is fine.
public final class LockedAppStore: @unchecked Sendable {
    private enum Key {
        static let enabled = "appLock.enabled"
        static let apps = "appLock.apps"
        static let defaultPolicyMigrated = "appLock.migratedToWhenAppOpens"
        static let privacyLevel = "appLock.privacyLevel"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var enabled: Bool {
        get { defaults.bool(forKey: Key.enabled) }
        set { defaults.set(newValue, forKey: Key.enabled) }
    }

    public var privacyLevel: PrivacyLevel {
        get {
            guard let rawValue = defaults.string(forKey: Key.privacyLevel),
                  let level = PrivacyLevel(rawValue: rawValue) else {
                return .normal
            }
            return level
        }
        set {
            defaults.set(newValue.rawValue, forKey: Key.privacyLevel)
        }
    }

    public var apps: [LockedApp] {
        guard let data = defaults.data(forKey: Key.apps),
            var apps = try? JSONDecoder().decode([LockedApp].self, from: data)
        else { return [] }
        if !defaults.bool(forKey: Key.defaultPolicyMigrated) {
            defaults.set(true, forKey: Key.defaultPolicyMigrated)
            var changed = false
            apps = apps.map { app in
                if case .afterMinutes(5) = app.policy {
                    var m = app
                    m.policy = .everyTime
                    changed = true
                    return m
                }
                return app
            }
            if changed { save(apps) }
        }
        return apps
    }

    @discardableResult
    public func add(bundleID: String, name: String, policy: RelockPolicy = .everyTime) -> Bool {
        guard !AppLockBlacklist.isProtected(bundleID), app(bundleID) == nil else { return false }
        save(apps + [LockedApp(bundleID: bundleID, name: name, policy: policy)])
        return true
    }

    public func remove(bundleID: String) {
        save(apps.filter { $0.bundleID != bundleID })
    }

    public func setPolicy(_ policy: RelockPolicy, for bundleID: String) {
        save(
            apps.map { app in
                var app = app
                if app.bundleID == bundleID { app.policy = policy }
                return app
            })
    }

    public func app(_ bundleID: String) -> LockedApp? {
        apps.first { $0.bundleID == bundleID }
    }

    public func isLocked(_ bundleID: String) -> Bool {
        enabled && app(bundleID) != nil
    }

    private func save(_ apps: [LockedApp]) {
        defaults.set(try? JSONEncoder().encode(apps), forKey: Key.apps)
    }
}
