import Foundation

/// Removes the pre-app background daemon (LaunchAgent + its copied binaries). Without
/// this, the old daemon and the app would both try to own the verification socket.
/// Enrollment and the stored password live elsewhere in the support directory and are
/// deliberately left alone.
public enum LegacyAgentMigration {
    public static let label = "com.faceunlock.daemon"

    public static func plistURL(home: URL) -> URL {
        home.appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    public static func binaryDirectory(home: URL) -> URL {
        home.appendingPathComponent("Library/Application Support/faceunlock/bin", isDirectory: true)
    }

    public static func needsMigration(home: URL) -> Bool {
        let manager = FileManager.default
        return manager.fileExists(atPath: plistURL(home: home).path)
            || manager.fileExists(atPath: binaryDirectory(home: home).path)
    }

    @discardableResult
    public static func migrateIfNeeded(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        unloadAgent: (String) -> Void = LegacyAgentMigration.bootout
    ) -> Bool {
        guard needsMigration(home: home) else { return false }
        unloadAgent(label)
        try? FileManager.default.removeItem(at: plistURL(home: home))
        try? FileManager.default.removeItem(at: binaryDirectory(home: home))
        return true
    }

    public static func bootout(_ label: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["bootout", "gui/\(getuid())/\(label)"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
    }
}
