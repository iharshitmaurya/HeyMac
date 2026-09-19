import Foundation

/// Apps that can never be locked: the tools needed to recover from a mistake, and this app.
public enum AppLockBlacklist {
    public static let bundleIDs: Set<String> = [
        "com.apple.Terminal", "com.googlecode.iterm2", "com.apple.finder",
        "com.apple.SystemSettings", "com.apple.systempreferences",
        "com.apple.ActivityMonitor", "com.apple.dt.Xcode", "com.microsoft.VSCode",
    ]

    public static func isProtected(_ bundleID: String, ownBundleID: String? = Bundle.main.bundleIdentifier) -> Bool {
        bundleIDs.contains(bundleID) || bundleID == ownBundleID
    }
}
