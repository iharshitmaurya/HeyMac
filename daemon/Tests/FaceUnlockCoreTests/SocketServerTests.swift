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

@Test func socketFileHasRestrictedPermissions() throws {
    let path = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).sock").path
    let server = SocketServer(path: path, handler: { _ in .ok })
    try server.start()
    defer { server.stop() }

    let attrs = try FileManager.default.attributesOfItem(atPath: path)
    let permissions = attrs[.posixPermissions] as! NSNumber
    #expect(permissions.intValue == 0o600)
}
