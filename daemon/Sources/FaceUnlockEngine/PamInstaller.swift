import Foundation

public enum PamStatus: Equatable, Sendable {
    case installed
    case notInstalled
    /// Module file and sudo_local disagree — e.g. a macOS update reset /etc/pam.d.
    case partial
}

public enum PamInstallerError: Error, Equatable {
    case resourcesMissing
    case cancelled
    case failed(String)
}

/// Installs and removes the sudo PAM module by running the bundled shell scripts with
/// administrator rights (the standard macOS password prompt — no privileged helper).
public struct PamInstaller: Sendable {
    public static let moduleInstallPath = "/usr/local/lib/pam/pam_faceunlock.so"
    public static let sudoLocalPath = "/etc/pam.d/sudo_local"

    private let resourcesDirectory: URL
    private let fileExists: @Sendable (String) -> Bool
    private let readFile: @Sendable (String) -> String?
    private let runAppleScript: @Sendable (String) throws -> Void

    public init(
        resourcesDirectory: URL,
        fileExists: @escaping @Sendable (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
        readFile: @escaping @Sendable (String) -> String? = { try? String(contentsOfFile: $0, encoding: .utf8) },
        runAppleScript: @escaping @Sendable (String) throws -> Void = PamInstaller.runAppleScript
    ) {
        self.resourcesDirectory = resourcesDirectory
        self.fileExists = fileExists
        self.readFile = readFile
        self.runAppleScript = runAppleScript
    }

    public func status() -> PamStatus {
        let moduleInstalled = fileExists(Self.moduleInstallPath)
        let referenced = readFile(Self.sudoLocalPath)?.contains(Self.moduleInstallPath) ?? false
        switch (moduleInstalled, referenced) {
        case (true, true): return .installed
        case (false, false): return .notInstalled
        default: return .partial
        }
    }

    public func install() throws {
        let script = resourcesDirectory.appendingPathComponent("install-pam.sh").path
        let module = resourcesDirectory.appendingPathComponent("pam_faceunlock.so").path
        guard fileExists(script), fileExists(module) else { throw PamInstallerError.resourcesMissing }
        try runAppleScript(Self.administratorScript(command: "/bin/bash \(Self.shellQuote(script)) \(Self.shellQuote(module))"))
    }

    public func uninstall() throws {
        let script = resourcesDirectory.appendingPathComponent("uninstall-pam.sh").path
        guard fileExists(script) else { throw PamInstallerError.resourcesMissing }
        try runAppleScript(Self.administratorScript(command: "/bin/bash \(Self.shellQuote(script))"))
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
            throw PamInstallerError.cancelled
        }
        throw PamInstallerError.failed(message.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
