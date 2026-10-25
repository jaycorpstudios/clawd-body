import Foundation
import HiloContract
import HiloCore
import HiloRuntime

let arguments = CommandLine.arguments.dropFirst()
func option(_ name: String) -> String? {
    guard let i = arguments.firstIndex(of: name), arguments.index(after: i) < arguments.endIndex else { return nil }
    return arguments[arguments.index(after: i)]
}

let host = option("--host") ?? "work"
let idle = Double(option("--away-after") ?? "120") ?? 120
let socketPath = option("--socket") ?? LocalSocket.defaultPath
let forceAway = arguments.contains("--always-away")

struct AlwaysAway: PresenceProbe {
    func userIsPresent() -> Bool { false }
}

let coordinator = Coordinator(
    host: host,
    mapper: HookMapper(repoRoot: GitRepo.root(of:)),
    link: StdoutLink(),
    presence: forceAway ? AlwaysAway() : SystemPresence(idleThresholdSeconds: idle) as PresenceProbe
)

do {
    try LocalSocket.serve(path: socketPath) { op, body in
        switch op {
        case "hook":
            guard let input = try? HookInput.decode(body) else { return HookResponse.passThrough }
            return await coordinator.handleHook(input)
        case "buddy":
            do {
                try await coordinator.handleBuddy(body)
                return Data("ok\n".utf8)
            } catch {
                return Data("rejected: \(error)\n".utf8)
            }
        default:
            return Data()
        }
    }
} catch {
    FileHandle.standardError.write(Data("hilod: cannot listen on \(socketPath): \(error)\n".utf8))
    exit(1)
}
FileHandle.standardError.write(Data("hilod: host \(host), socket \(socketPath)\n".utf8))
dispatchMain()
