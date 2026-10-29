import Darwin
import Foundation

/// One request per connection: first line is the operation, the rest is the body. The server replies and closes.
public enum LocalSocket {
    public static let maxBody = 1 << 20

    /// `HILO_SOCKET` points the app, the CLI and `hilod` at a scratch daemon during development.
    public static var defaultPath: String {
        if let path = ProcessInfo.processInfo.environment["HILO_SOCKET"] { return path }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appending(path: "Hilo/hilod.sock").path(percentEncoded: false)
    }

    public enum SocketError: Error { case pathTooLong, system(String) }

    /// The handler also gets the client's pid, so it can tell when a long-waiting client was killed.
    public static func serve(path: String, handler: @escaping @Sendable (String, Data, pid_t) async -> Data) throws {
        let dir = URL(filePath: path).deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path(percentEncoded: false))
        unlink(path)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw SocketError.system("socket") }
        var addr = try address(path)
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0, chmod(path, 0o600) == 0, listen(fd, 16) == 0 else {
            close(fd)
            throw SocketError.system("bind/listen \(errno)")
        }

        Thread.detachNewThread {
            while true {
                let client = accept(fd, nil, nil)
                guard client >= 0 else { continue }
                guard peerIsSameUser(client) else { close(client); continue }
                DispatchQueue.global().async {
                    guard let (op, body) = readRequest(client) else { close(client); return }
                    let pid = peerPid(client)
                    Task {
                        let reply = await handler(op, body, pid)
                        writeAll(client, reply)
                        close(client)
                    }
                }
            }
        }
    }

    /// nil when the daemon is unreachable; callers must then fail open.
    public static func request(path: String, op: String, body: Data, timeoutSeconds: Int) -> Data? {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var timeout = timeval(tv_sec: timeoutSeconds, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        guard var addr = try? address(path) else { return nil }
        let connected = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard connected == 0 else { return nil }
        writeAll(fd, Data((op + "\n").utf8) + body)
        shutdown(fd, SHUT_WR)
        return readAll(fd)
    }

    private static func address(_ path: String) throws -> sockaddr_un {
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: addr.sun_path) else { throw SocketError.pathTooLong }
        withUnsafeMutableBytes(of: &addr.sun_path) { buffer in
            buffer.copyBytes(from: bytes)
        }
        return addr
    }

    private static func peerIsSameUser(_ fd: Int32) -> Bool {
        var uid: uid_t = 0
        var gid: gid_t = 0
        return getpeereid(fd, &uid, &gid) == 0 && uid == getuid()
    }

    private static func peerPid(_ fd: Int32) -> pid_t {
        var pid: pid_t = 0
        var size = socklen_t(MemoryLayout<pid_t>.size)
        return getsockopt(fd, SOL_LOCAL, LOCAL_PEERPID, &pid, &size) == 0 ? pid : 0
    }

    private static func readRequest(_ fd: Int32) -> (String, Data)? {
        guard let raw = readAll(fd), let newline = raw.firstIndex(of: UInt8(ascii: "\n")) else { return nil }
        let op = String(decoding: raw[raw.startIndex..<newline], as: UTF8.self)
        return (op, Data(raw[raw.index(after: newline)...]))
    }

    private static func readAll(_ fd: Int32) -> Data? {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16_384)
        while true {
            let n = read(fd, &buffer, buffer.count)
            if n == 0 { return data }
            if n < 0 { return nil }
            data.append(contentsOf: buffer[0..<n])
            if data.count > maxBody { return nil }
        }
    }

    private static func writeAll(_ fd: Int32, _ data: Data) {
        data.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                let n = write(fd, raw.baseAddress! + offset, raw.count - offset)
                if n <= 0 { return }
                offset += n
            }
        }
    }
}

/// The `hilo hook` process on the other end of a held request.
public struct HookPeer: Sendable {
    public let pid: pid_t
    public init(pid: pid_t) { self.pid = pid }
    @Sendable public func isAlive() -> Bool { kill(pid, 0) == 0 }
}
