import Foundation
import Testing
import HiloContract
import HiloCore
@testable import HiloRuntime

actor DeskLink: BuddyLink {
    var raw: [Data] = []
    func send(_ data: Data) async { raw.append(data) }
    func decoded() -> [Outbound] { raw.compactMap { try? Wire.decodeOutbound($0).body } }
    func types() -> [String] { decoded().map(\.type) }
}

struct DeskAway: PresenceProbe { func userIsPresent() -> Bool { false } }

func buddyMessage(_ type: String, _ data: String) -> Data {
    Data(#"{"v":1,"id":"\#(ULID.make())","ts":1000,"type":"\#(type)","data":\#(data)}"#.utf8)
}

@Suite struct SettingsFlowTests {
    let link = DeskLink()
    let coordinator: Coordinator

    init() {
        coordinator = Coordinator(host: "work", mapper: HookMapper(repoRoot: { _ in nil }), link: link, presence: DeskAway())
    }

    @Test func changeIsSentAndOnlyTheBuddysAnswerIsReported() async throws {
        #expect(await coordinator.changeSettings(SettingsChange(sound: true, volume: 0)))
        #expect(await link.decoded() == [.settingsSet(SettingsChange(sound: true, volume: 0))])
        #expect(await coordinator.settings == nil)
        try await coordinator.handleBuddy(buddyMessage("device.settings", #"{"sound":true,"volume":0,"brightness":80}"#))
        #expect(await coordinator.settings == DeviceSettings(sound: true, volume: 0, brightness: 80))
        await coordinator.buddyLink(up: false)
        #expect(await coordinator.settings == nil)
    }

    @Test func invalidChangesAreNotSent() async {
        #expect(await coordinator.changeSettings(SettingsChange()) == false)
        #expect(await coordinator.changeSettings(SettingsChange(volume: 101)) == false)
        #expect(await coordinator.changeSettings(SettingsChange(brightness: 9)) == false)
        #expect(await link.raw.isEmpty)
    }

    @Test func settingsOpForwardsAndStatusCarriesTheReport() async throws {
        let ops = ControlOps(coordinator: coordinator, buddy: nil, configPath: "/nonexistent/config.json", tokensFromTranscripts: false)
        let rejected = String(decoding: await ops.handle(op: "settings", body: Data(#"{"volume":300}"#.utf8)) ?? Data(), as: UTF8.self)
        #expect(rejected.hasPrefix("rejected"))
        _ = await ops.handle(op: "settings", body: Data(#"{"brightness":40}"#.utf8))
        #expect(await link.decoded() == [.settingsSet(SettingsChange(brightness: 40))])
        try await coordinator.handleBuddy(buddyMessage("device.settings", #"{"sound":false,"volume":60,"brightness":40}"#))
        let status = try JSONDecoder().decode(DaemonStatus.self, from: try #require(await ops.handle(op: "status", body: Data())))
        #expect(status.settings == DeviceSettings(sound: false, volume: 60, brightness: 40))
    }
}
