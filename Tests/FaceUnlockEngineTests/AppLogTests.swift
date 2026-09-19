import Testing
import Foundation
@testable import FaceUnlockEngine

private func makeLogURL() -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appendingPathComponent("FaceUnlock.log")
}

@Test func logLinesAreTimestampedAndAppended() throws {
    let url = makeLogURL()
    let log = AppLog(url: url, alsoStandardError: false, now: { Date(timeIntervalSince1970: 0) })
    log.write("first")
    log.write("second")

    let contents = try String(contentsOf: url, encoding: .utf8)
    let lines = contents.split(separator: "\n")
    #expect(lines.count == 2)
    #expect(lines[0].hasSuffix("] first"))
    #expect(lines[1].hasSuffix("] second"))
    #expect(lines[0].hasPrefix("["))
}

@Test func theLogRotatesOnceItGetsBig() throws {
    let url = makeLogURL()
    let log = AppLog(url: url, maxBytes: 120, alsoStandardError: false)
    for index in 0..<10 { log.write("line \(index) with some padding to fill the file") }

    let current = try String(contentsOf: url, encoding: .utf8)
    #expect(current.contains("line 9"))
    #expect(!current.contains("line 0"))
    #expect(FileManager.default.fileExists(atPath: log.rotatedURL.path))
    #expect(current.utf8.count <= 120)
}
