import Foundation
import HiloRuntime

let arguments = Array(CommandLine.arguments.dropFirst())
let socketPath = ProcessInfo.processInfo.environment["HILO_SOCKET"] ?? LocalSocket.defaultPath

switch arguments.first {
case "hook":
    // Must never block or break Claude Code: any failure prints nothing and exits 0.
    let input = FileHandle.standardInput.readDataToEndOfFile()
    if let reply = LocalSocket.request(path: socketPath, op: "hook", body: input, timeoutSeconds: 650) {
        FileHandle.standardOutput.write(reply)
    }
    exit(0)
case "buddy" where arguments.count == 2:
    guard let reply = LocalSocket.request(path: socketPath, op: "buddy", body: Data(arguments[1].utf8), timeoutSeconds: 5) else {
        FileHandle.standardError.write(Data("hilo: hilod is not running\n".utf8))
        exit(1)
    }
    FileHandle.standardOutput.write(reply)
default:
    FileHandle.standardError.write(Data("""
    usage:
      hilo hook              read a Claude Code hook payload on stdin (configured in settings.json)
      hilo buddy '<json>'    send a buddy -> Mac message to hilod (development)

    """.utf8))
    exit(2)
}
