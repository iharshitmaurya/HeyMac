import Foundation

/// Timestamped events in ~/Library/Logs/FaceUnlock.log — scores and errors, never
/// images or passwords. Rotates at `maxBytes`, keeping one previous file.
public final class AppLog: @unchecked Sendable {
    public static let shared = AppLog(
        url: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/FaceUnlock.log")
    )

    public let url: URL
    private let maxBytes: Int
    private let now: () -> Date
    private let alsoStandardError: Bool
    private let lock = NSLock()
    private let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone.current
        return formatter
    }()

    public init(url: URL, maxBytes: Int = 1_000_000, alsoStandardError: Bool = true, now: @escaping () -> Date = Date.init) {
        self.url = url
        self.maxBytes = maxBytes
        self.alsoStandardError = alsoStandardError
        self.now = now
    }

    public var rotatedURL: URL { url.appendingPathExtension("1") }

    public func write(_ message: String) {
        let line = "[\(formatter.string(from: now()))] \(message)\n"
        lock.withLock {
            let manager = FileManager.default
            try? manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let size = (try? manager.attributesOfItem(atPath: url.path)[.size] as? NSNumber)??.intValue ?? 0
            if size + line.utf8.count > maxBytes {
                try? manager.removeItem(at: rotatedURL)
                try? manager.moveItem(at: url, to: rotatedURL)
            }
            if !manager.fileExists(atPath: url.path) {
                manager.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600])
            }
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(Data(line.utf8))
                try? handle.close()
            }
        }
        if alsoStandardError { FileHandle.standardError.write(Data(line.utf8)) }
    }
}
