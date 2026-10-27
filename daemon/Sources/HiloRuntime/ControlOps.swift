import Foundation
import HiloContract
import HiloCore

public protocol BuddyControl: Sendable {
    func status() -> BuddyStatus
    func startPairing() -> Bool
    func cancelPairing()
    func reconnect()
}

extension BLECentral: BuddyControl {}

/// Socket ops the Hilo app uses: `status`, `pair`, `pair-cancel`, `host`, `settings`, `face`, `pomodoro`, `music` and `session-look`. Each replies with a `DaemonStatus`.
public struct ControlOps: Sendable {
    private let coordinator: Coordinator
    private let buddy: BuddyControl?
    private let configPath: String
    private let tokensFromTranscripts: Bool
    private let access: @Sendable (String) -> AutomationAccess

    public init(coordinator: Coordinator, buddy: BuddyControl?, configPath: String = HiloConfig.defaultPath,
                tokensFromTranscripts: Bool, access: @escaping @Sendable (String) -> AutomationAccess = AutomationAccess.check) {
        self.coordinator = coordinator; self.buddy = buddy
        self.configPath = configPath; self.tokensFromTranscripts = tokensFromTranscripts; self.access = access
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
        case "face":
            await coordinator.setFace(RGB565Image.load(URL(filePath: HiloConfig.facePath(configPath: configPath))))
        case "settings":
            guard let change = try? JSONDecoder().decode(SettingsChange.self, from: body),
                  await coordinator.changeSettings(change) else { return Data("rejected: bad settings\n".utf8) }
        case "pomodoro":
            guard let command = Self.pomodoroCommand(body), await coordinator.changePomodoro(command) else {
                return Data("rejected: bad pomodoro command\n".utf8)
            }
        case "session-look":
            guard let change = try? JSONDecoder().decode(SessionLookChange.self, from: body),
                  await coordinator.changeLook(change) != nil else { return Data("rejected: unknown session or accessory\n".utf8) }
        case "music":
            let config = HiloConfig.load(path: configPath)
            await coordinator.followMusic(spotify: config.musicSpotify ?? true, app: config.musicApp ?? true)
            let (spotify, app) = await coordinator.followedMusic
            return await status(music: MusicStatus(spotify: spotify, app: app, spotifyAccess: access(AppleScriptPlayer.spotify),
                                                   appAccess: access(AppleScriptPlayer.music)))
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

    private func status(music: MusicStatus? = nil) async -> Data {
        let status = DaemonStatus(host: await coordinator.currentHost,
                                  buddy: buddy?.status() ?? BuddyStatus(link: .noBluetooth),
                                  tokensFromTranscripts: tokensFromTranscripts,
                                  settings: await coordinator.settings, face: await coordinator.faceHash,
                                  pomodoro: await coordinator.focus, music: music)
        return (try? JSONEncoder().encode(status)) ?? Data()
    }

    private struct PomodoroBody: Decodable {
        var action: String
        var workMin: Int?
        var breakMin: Int?
        var on: Bool?
        enum CodingKeys: String, CodingKey { case action, workMin = "work_min", breakMin = "break_min", on }
    }

    /// `{"action":"toggle"}`, `{"action":"reset"}`, `{"action":"durations","work_min":50,"break_min":10}` or `{"action":"auto_continue","on":true}`.
    static func pomodoroCommand(_ body: Data) -> PomodoroCommand? {
        guard let b = try? JSONDecoder().decode(PomodoroBody.self, from: body) else { return nil }
        switch b.action {
        case "toggle": return .toggle
        case "reset": return .reset
        case "durations" where b.workMin != nil || b.breakMin != nil: return .durations(work: b.workMin, rest: b.breakMin)
        case "auto_continue": return b.on.map { .autoContinue($0) }
        default: return nil
        }
    }
}
