import Foundation

public struct InstalledApp: Equatable, Sendable, Identifiable {
    public let bundleID: String
    public let name: String
    public let url: URL
    public var id: String { bundleID }
}

/// Finds installed `.app` bundles for the "which apps to lock" picker.
public enum InstalledApps {
    public static var defaultRoots: [URL] {
        [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/System/Applications"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications"),
        ]
    }

    public static func scan(roots: [URL] = defaultRoots, fileManager: FileManager = .default) -> [InstalledApp] {
        var found: [String: InstalledApp] = [:]
        for root in roots {
            guard let enumerator = fileManager.enumerator(
                at: root, includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }
            for case let url as URL in enumerator {
                if url.pathExtension == "app" {
                    if let app = load(url), found[app.bundleID] == nil { found[app.bundleID] = app }
                } else if enumerator.level >= 2 {
                    enumerator.skipDescendants() // folders like Utilities/ only, not the whole disk
                }
            }
        }
        return found.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static func load(_ url: URL) -> InstalledApp? {
        guard let bundle = Bundle(url: url), let bundleID = bundle.bundleIdentifier,
              !AppLockBlacklist.isProtected(bundleID) else { return nil }
        let info = bundle.infoDictionary ?? [:]
        if info["LSBackgroundOnly"] as? Bool == true { return nil }
        let name = (info["CFBundleDisplayName"] as? String)
            ?? (info["CFBundleName"] as? String)
            ?? url.deletingPathExtension().lastPathComponent
        return InstalledApp(bundleID: bundleID, name: name, url: url)
    }
}
