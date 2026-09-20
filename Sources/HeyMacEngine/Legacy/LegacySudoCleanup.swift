import Foundation

public enum LegacySudoCleanupError: Error, Equatable {
    case scriptMissing
    case cancelled
    case failed(String)
}

/// Sudo face unlock was removed from the app. Older versions installed a PAM module and a
/// line in /etc/pam.d/sudo_local; this detects those leftovers and removes them with the
/// bundled uninstall script (the standard macOS administrator prompt, no privileged helper).
public struct LegacySudoCleanup: Sendable {
    public static let moduleInstallPath = "/usr/local/lib/pam/pam_faceunlock.so"
    public static let sudoLocalPath = "/etc/pam.d/sudo_local"

    private let scriptURL: URL
    private let fileExists: @Sendable (String) -> Bool
    private let readFile: @Sendable (String) -> String?
    private let runAppleScript: @Sendable (String) throws -> Void

    public init(
        scriptURL: URL,
        fileExists: @escaping @Sendable (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
        readFile: @escaping @Sendable (String) -> String? = { try? String(contentsOfFile: $0, encoding: .utf8) },
        runAppleScript: @escaping @Sendable (String) throws -> Void = LegacySudoCleanup.runAppleScript
    ) {
        self.scriptURL = scriptURL
        self.fileExists = fileExists
        self.readFile = readFile
        self.runAppleScript = runAppleScript
    }

    /// True if the old module file or the line that loads it is still on this Mac.
    public func leftoverDetected() -> Bool {
        fileExists(Self.moduleInstallPath)
            || (readFile(Self.sudoLocalPath)?.contains(Self.moduleInstallPath) ?? false)
    }

    public func remove() throws {
        guard fileExists(scriptURL.path) else { throw LegacySudoCleanupError.scriptMissing }
        try runAppleScript(Self.administratorScript(command: "/bin/bash \(Self.shellQuote(scriptURL.path))"))
    }

    static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func administratorScript(command: String) -> String {
        let escaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "do shell script \"\(escaped)\" with administrator privileges"
    }

    public static let runAppleScript: @Sendable (String) throws -> Void = { source in
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", source]
        let errors = Pipe()
        process.standardError = errors
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        let message = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        process.waitUntilExit()
        guard process.terminationStatus != 0 else { return }
        if message.contains("-128") || message.localizedCaseInsensitiveContains("cancel") {
            throw LegacySudoCleanupError.cancelled
        }
        throw LegacySudoCleanupError.failed(message.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
