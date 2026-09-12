import Foundation
#if canImport(Darwin)
import Darwin
#endif

public enum SocketServerError: Error, Equatable {
    case socketCreationFailed
    case bindFailed
    case listenFailed
}

public final class SocketServer: @unchecked Sendable {
    private let path: String
    private let handler: (WireMessage) -> WireMessage
    private let stateLock = NSLock()
    private var listenFD: Int32 = -1
    private var running = false
    private let queue = DispatchQueue(label: "faceunlock.socketserver")

    public init(path: String, handler: @escaping (WireMessage) -> WireMessage) {
        self.path = path
        self.handler = handler
    }

    public func start() throws {
        unlink(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw SocketServerError.socketCreationFailed }
        stateLock.withLock { listenFD = fd }

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
        let bindResult = withUnsafePointer(to: &addr) { ptr -> Int32 in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, addrSize) }
        }
        guard bindResult == 0 else { throw SocketServerError.bindFailed }
        chmod(path, 0o600)
        guard listen(fd, 8) == 0 else { throw SocketServerError.listenFailed }

        stateLock.withLock { running = true }
        queue.async { [weak self] in self?.acceptLoop() }
    }

    private func acceptLoop() {
        while stateLock.withLock({ running }) {
            let fd = stateLock.withLock { listenFD }
            let clientFD = accept(fd, nil, nil)
            guard clientFD >= 0 else {
                guard stateLock.withLock({ running }) else { break }
                // ponytail: brief sleep instead of a tight spin on repeated accept() failures
                usleep(10_000)
                continue
            }
            handle(clientFD)
        }
    }

    private func handle(_ fd: Int32) {
        defer { close(fd) }
        var buffer = [UInt8](repeating: 0, count: 256)
        let bytesRead = read(fd, &buffer, buffer.count)
        guard bytesRead > 0, let message = WireMessage.decode(Data(buffer[0..<bytesRead])) else { return }
        let response = handler(message).encoded()
        response.withUnsafeBytes { raw in _ = write(fd, raw.baseAddress, raw.count) }
    }

    public func stop() {
        stateLock.withLock {
            running = false
            if listenFD >= 0 {
                shutdown(listenFD, SHUT_RDWR)
                close(listenFD)
                listenFD = -1
            }
        }
        unlink(path)
    }
}
