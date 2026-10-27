import Foundation
import HiloContract

public protocol BuddyControl: Sendable {
    func status() -> BuddyStatus
    func startPairing() -> Bool
    func cancelPairing()
    func reconnect()
}

extension BLECentral: BuddyControl {}

/// Socket ops the Hilo app uses to set this Mac up: `status`, `pair`, `pair-cancel`, `host` and `settings`. Each replies with a `DaemonStatus`.
public struct ControlOps: Sendable {
    private let coordinator: Coordinator
    private let buddy: BuddyControl?
    private let configPath: String
    private let tokensFromTranscripts: Bool

    public init(coordinator: Coordinator, buddy: BuddyControl?, configPath: String = HiloConfig.defaultPath,
                tokensFromTranscripts: Bool) {
        self.coordinator = coordinator; self.buddy = buddy
        self.configPath = configPath; self.tokensFromTranscripts = tokensFromTranscripts
    }

    /// nil for an op this handler does not own.
    public func handle(op: String, body: Data) async -> Data? {
        switch op {
        case "status":
            break
        case "pair":
            _ = buddy?.startPairing()
        case "pair-cancel":
            buddy?.cancelPairing()
        case "settings":
            guard let change = try? JSONDecoder().decode(SettingsChange.self, from: body),
                  await coordinator.changeSettings(change) else { return Data("rejected: bad settings\n".utf8) }
        case "host":
            guard let name = HiloConfig.hostName(from: String(decoding: body, as: UTF8.self)) else {
                return Data("rejected: empty host name\n".utf8)
            }
            var config = HiloConfig.load(path: configPath)
            config.host = name
            do { try config.save(path: configPath) } catch { return Data("rejected: \(error)\n".utf8) }
            if await coordinator.currentHost != name {
                await coordinator.setHost(name)
                buddy?.reconnect()
            }
        default:
            return nil
        }
        return await status()
    }

    private func status() async -> Data {
        let status = DaemonStatus(host: await coordinator.currentHost,
                                  buddy: buddy?.status() ?? BuddyStatus(link: .noBluetooth),
                                  tokensFromTranscripts: tokensFromTranscripts,
                                  settings: await coordinator.settings)
        return (try? JSONEncoder().encode(status)) ?? Data()
    }
}
