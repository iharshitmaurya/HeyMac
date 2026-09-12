import Testing
import Foundation
#if canImport(Darwin)
import Darwin
#endif
@testable import FaceUnlockCore

func sendAndReceive(_ message: WireMessage, to path: String) -> WireMessage? {
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { return nil }
    defer { close(fd) }

    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    let pathBytes = Array(path.utf8)
    withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
        ptr.withMemoryRebound(to: CChar.self, capacity: 104) { cptr in
            for (i, byte) in pathBytes.enumerated() where i < 103 { cptr[i] = CChar(bitPattern: byte) }
            cptr[min(pathBytes.count, 103)] = 0
        }
    }
    let addrSize = socklen_t(MemoryLayout<sockaddr_un>.size)
    let connected = withUnsafePointer(to: &addr) { ptr -> Int32 in
        ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, addrSize) }
    }
    guard connected == 0 else { return nil }

    let request = message.encoded()
    request.withUnsafeBytes { raw in _ = write(fd, raw.baseAddress, raw.count) }
    var buffer = [UInt8](repeating: 0, count: 256)
    let n = read(fd, &buffer, buffer.count)
    guard n > 0 else { return nil }
    return WireMessage.decode(Data(buffer[0..<n]))
}

@Test func serverRespondsAccordingToHandler() throws {
    let path = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).sock").path
    let server = SocketServer(path: path, handler: { message in
        message == .verifyLock ? .ok : .fail
    })
    try server.start()
    defer { server.stop() }

    Thread.sleep(forTimeInterval: 0.1)
    #expect(sendAndReceive(.verifyLock, to: path) == .ok)
    #expect(sendAndReceive(.verify, to: path) == .fail)
}

// MARK: - Finding 4: a client that connects and never writes must not wedge the accept loop

func connectOnly(to path: String) -> Int32 {
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { return -1 }
    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    let pathBytes = Array(path.utf8)
    withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
        ptr.withMemoryRebound(to: CChar.self, capacity: 104) { cptr in
            for (i, byte) in pathBytes.enumerated() where i < 103 { cptr[i] = CChar(bitPattern: byte) }
            cptr[min(pathBytes.count, 103)] = 0
        }
    }
    let addrSize = socklen_t(MemoryLayout<sockaddr_un>.size)
    _ = withUnsafePointer(to: &addr) { ptr -> Int32 in
        ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, addrSize) }
    }
    return fd
}

@Test func silentClientDoesNotWedgeSubsequentConnections() throws {
    let path = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).sock").path
    let server = SocketServer(path: path, handler: { message in
        message == .verifyLock ? .ok : .fail
    })
    try server.start()
    defer { server.stop() }
    Thread.sleep(forTimeInterval: 0.1)

    // Connect and never write anything.
    let silentFD = connectOnly(to: path)
    defer { close(silentFD) }

    // A second, well-behaved client must still eventually get served: the silent
    // connection's blocking read() is bounded by the 5s SO_RCVTIMEO set on accept, after
    // which the accept loop moves on and services the next connection. Without that
    // timeout this would hang indefinitely (no automated substitute needed — this test
    // itself times out the whole suite if the fix regresses).
    let start = Date()
    #expect(sendAndReceive(.verifyLock, to: path) == .ok)
    #expect(Date().timeIntervalSince(start) < 8.0)
}

@Test func socketFileHasRestrictedPermissions() throws {
    let path = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).sock").path
    let server = SocketServer(path: path, handler: { _ in .ok })
    try server.start()
    defer { server.stop() }

    let attrs = try FileManager.default.attributesOfItem(atPath: path)
    let permissions = attrs[.posixPermissions] as! NSNumber
    #expect(permissions.intValue == 0o600)
}
