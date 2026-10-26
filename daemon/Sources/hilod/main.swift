import Foundation
import HiloContract
import HiloCore
import HiloRuntime
import HiloStore

let arguments = CommandLine.arguments.dropFirst()
func option(_ name: String) -> String? {
    guard let i = arguments.firstIndex(of: name), arguments.index(after: i) < arguments.endIndex else { return nil }
    return arguments[arguments.index(after: i)]
}

let host = option("--host") ?? "work"
let idle = Double(option("--away-after") ?? "120") ?? 120
let socketPath = option("--socket") ?? LocalSocket.defaultPath
let forceAway = arguments.contains("--always-away")
let useStdout = arguments.contains("--stdout")
let pair = arguments.contains("--pair")

let log: @Sendable (String) -> Void = { FileHandle.standardError.write(Data("hilod: \($0)\n".utf8)) }

struct AlwaysAway: PresenceProbe {
    func userIsPresent() -> Bool { false }
}

let central = useStdout ? nil : BLECentral(trusted: TrustedBuddies(), pairing: pair, log: log)
let session = central.map { BuddySession(writer: $0) }

let recorder: StoreRecorder?
do {
    recorder = StoreRecorder(store: try HiloStore(), log: log)
} catch {
    log("Hilo store unavailable, sessions are not recorded: \(error)")
    recorder = nil
}

let coordinator = Coordinator(
    host: host,
    mapper: HookMapper(repoRoot: GitRepo.root(of:)),
    link: session ?? StdoutLink() as BuddyLink,
    presence: forceAway ? AlwaysAway() : SystemPresence(idleThresholdSeconds: idle) as PresenceProbe,
    recorder: recorder,
    log: log
)

if let central, let session {
    Task {
        await session.setHandlers(
            onUp: { await coordinator.sendSnapshot() },
            onMessage: { data in
                do { try await coordinator.handleBuddy(data) } catch { log("buddy message rejected: \(error)") }
            })
        for await event in central.events {
            await coordinator.buddyLink(up: event != .down)
            await session.handle(event)
        }
    }
}

do {
    try LocalSocket.serve(path: socketPath) { op, body in
        switch op {
        case "hook":
            guard let input = try? HookInput.decode(body) else { return HookResponse.passThrough }
            return await coordinator.handleHook(input)
        case "hilo":
            await coordinator.sendSnapshot()
            return Data("ok\n".utf8)
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
