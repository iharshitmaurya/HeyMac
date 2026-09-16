import Testing
import Foundation
#if canImport(Darwin)
import Darwin
#endif
import FaceUnlockCore
@testable import FaceUnlockEngine

/// Short path: a Unix socket path must fit in 104 bytes, which temp directories blow past.
private func makeSocketPath() -> String {
    "/tmp/fu-test-\(UUID().uuidString.prefix(8)).sock"
}

private func sendVerify(to path: String) -> String? {
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { return nil }
    defer { close(fd) }
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    let bytes = Array(path.utf8)
    withUnsafeMutablePointer(to: &address.sun_path) { pointer in
        pointer.withMemoryRebound(to: CChar.self, capacity: 104) { chars in
            for (index, byte) in bytes.enumerated() where index < 103 { chars[index] = CChar(bitPattern: byte) }
            chars[min(bytes.count, 103)] = 0
        }
    }
    let size = socklen_t(MemoryLayout<sockaddr_un>.size)
    let connected = withUnsafePointer(to: &address) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, size) }
    }
    guard connected == 0 else { return nil }
    _ = "VERIFY\n".withCString { write(fd, $0, strlen($0)) }
    var buffer = [UInt8](repeating: 0, count: 64)
    let count = read(fd, &buffer, buffer.count)
    guard count > 0 else { return nil }
    return String(decoding: buffer[0..<count], as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
}

private func makeController(
    settings: EngineSettings, matcher: FakeMatcher, socketPath: String, recorder: EventRecorder = EventRecorder()
) -> EngineController {
    let system = FakeSystem()
    system.locked = false
    return EngineController(
        settings: settings, socketPath: socketPath,
        log: AppLog(url: FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).log"), alsoStandardError: false),
        makeMatcher: { matcher }, lockScreenEnvironment: system.environment(),
        typist: FakeTypist(system: system, unlocks: true), onEvent: { recorder.record($0) }
    )
}

@Test func theSocketAnswersOkWhenTheFaceMatches() throws {
    let settings = makeTestSettings { $0.sudoEnabled = true }
    let matcher = FakeMatcher()
    matcher.outcome = matchedOutcome()
    let recorder = EventRecorder()
    let path = makeSocketPath()
    let controller = makeController(settings: settings, matcher: matcher, socketPath: path, recorder: recorder)

    try controller.start()
    defer { controller.stop() }

    #expect(sendVerify(to: path) == "OK")
    #expect(matcher.callCount == 1)
    #expect(recorder.events == [.sudo(matched: true, summary: matchedOutcome().summary)])
}

@Test func pausedRefusesWithoutUsingTheCamera() throws {
    let settings = makeTestSettings {
        $0.sudoEnabled = true
        $0.paused = true
    }
    let matcher = FakeMatcher()
    matcher.outcome = matchedOutcome()
    let path = makeSocketPath()
    let controller = makeController(settings: settings, matcher: matcher, socketPath: path)

    try controller.start()
    defer { controller.stop() }

    #expect(sendVerify(to: path) == "FAIL")
    #expect(matcher.callCount == 0)
}

@Test func sudoTurnedOffRefuses() throws {
    let settings = makeTestSettings()
    let matcher = FakeMatcher()
    matcher.outcome = matchedOutcome()
    let path = makeSocketPath()
    let controller = makeController(settings: settings, matcher: matcher, socketPath: path)

    try controller.start()
    defer { controller.stop() }

    #expect(sendVerify(to: path) == "FAIL")
    #expect(matcher.callCount == 0)
}

@Test func nothingListensBeforeSetupIsComplete() throws {
    let settings = makeTestSettings { $0.setupComplete = false }
    let path = makeSocketPath()
    let controller = makeController(settings: settings, matcher: FakeMatcher(), socketPath: path)

    try controller.start()
    defer { controller.stop() }

    #expect(controller.isRunning == false)
    #expect(sendVerify(to: path) == nil)
}

@Test func stoppingClosesTheSocket() throws {
    let settings = makeTestSettings { $0.sudoEnabled = true }
    let matcher = FakeMatcher()
    matcher.outcome = matchedOutcome()
    let path = makeSocketPath()
    let controller = makeController(settings: settings, matcher: matcher, socketPath: path)

    try controller.start()
    #expect(sendVerify(to: path) == "OK")
    controller.stop()

    #expect(controller.isRunning == false)
    #expect(sendVerify(to: path) == nil)
}
