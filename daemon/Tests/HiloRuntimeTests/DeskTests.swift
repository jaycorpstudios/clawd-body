import CoreGraphics
import Foundation
import Testing
import HiloContract
import HiloCore
import HiloStore
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

private func solidImage(width: Int, height: Int, rgb: (UInt8, UInt8, UInt8)) -> CGImage {
    var bytes = [UInt8](repeating: 255, count: width * height * 4)
    for i in 0..<(width * height) { (bytes[i * 4], bytes[i * 4 + 1], bytes[i * 4 + 2]) = rgb }
    let provider = CGDataProvider(data: Data(bytes) as CFData)!
    return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                   space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                   provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
}

@Suite struct FaceTests {
    @Test func rendersAFixedRGB565SquareInChunksUnderTheCap() throws {
        let face = try #require(FaceImage.render(solidImage(width: 300, height: 200, rgb: (255, 0, 0))))
        #expect(face.pixels.count == FaceImage.side * FaceImage.side * 2)
        #expect(face.pixels.prefix(2) == Data([0x00, 0xF8]))
        let chunks = face.chunks
        #expect(chunks.count == 7)
        #expect(chunks.allSatisfy { $0.data.count <= 6000 && $0.count == 7 && $0.hash == face.hash && $0.w == 120 && $0.h == 120 })
        let joined = chunks.reduce(Data()) { $0 + Data(base64Encoded: $1.data)! }
        #expect(joined == face.pixels)
        for chunk in chunks {
            let bytes = try Wire.encode(.face(chunk), host: "work")
            #expect(bytes.count < 8 * 1024)
        }
    }

    @Test func hashMatchesTheSharedFixture() throws {
        let url = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../../../shared/fixtures/valid/host.face.json").standardized
        guard case .face(let chunk) = try Wire.decodeOutbound(Data(contentsOf: url)).body else { Issue.record("not a face"); return }
        #expect(FaceImage(pixels: try #require(Data(base64Encoded: chunk.data))).hash == chunk.hash)
    }

    @Test func coordinatorSendsTheFaceAnswersRequestsAndClearsIt() async throws {
        let link = DeskLink()
        let coordinator = Coordinator(host: "work", mapper: HookMapper(repoRoot: { _ in nil }), link: link, presence: DeskAway())
        let face = try #require(FaceImage.render(solidImage(width: 64, height: 64, rgb: (0, 0, 255))))
        await coordinator.setFace(face)
        #expect(await link.types() == Array(repeating: "host.face", count: 7) + ["snapshot"])
        guard case .snapshot(let snap) = await link.decoded().last else { Issue.record("no snapshot"); return }
        #expect(snap.face == FaceRef(hash: face.hash))

        try await coordinator.handleBuddy(buddyMessage("device.face_request", #"{"hash":"\#(face.hash)"}"#))
        #expect(await link.types().count == 15)
        try await coordinator.handleBuddy(buddyMessage("device.face_request", #"{"hash":"0123456789abcdef"}"#))
        #expect(await link.types().count == 15)

        await coordinator.setFace(nil)
        guard case .snapshot(let cleared) = await link.decoded().last else { Issue.record("no snapshot"); return }
        #expect(cleared.face == nil)
        #expect(await coordinator.faceHash == nil)
    }
}

final class DeskClock: Clock, @unchecked Sendable {
    private let lock = NSLock()
    private var t: Int
    init(_ t: Int) { self.t = t }
    func now() -> Int { lock.withLock { t } }
    func set(_ v: Int) { lock.withLock { t = v } }
    func sleep(seconds: Double) async { await Task.yield() }
}

@Suite struct PomodoroFlowTests {
    let link = DeskLink()
    let clock = DeskClock(10_000)
    let store: HiloStore
    let coordinator: Coordinator

    init() throws {
        let path = FileManager.default.temporaryDirectory.appending(path: "hilo-pomo-\(UUID().uuidString).sqlite")
        store = try HiloStore(path: path.path(percentEncoded: false))
        coordinator = Coordinator(host: "work", mapper: HookMapper(repoRoot: { _ in nil }), link: link, presence: DeskAway(),
                                  clock: clock, recorder: StoreRecorder(store: store))
    }

    @Test func commandsGoToTheBuddyAndIntoTheSnapshot() async throws {
        #expect(await coordinator.changePomodoro(.toggle))
        guard case .pomodoro(let p) = await link.decoded().last else { Issue.record("no pomodoro"); return }
        #expect(p.state == .running && p.endsAt == 10_000 + 25 * 60)
        await coordinator.sendSnapshot()
        guard case .snapshot(let snap) = await link.decoded().last else { Issue.record("no snapshot"); return }
        #expect(snap.pomodoro == p)
        #expect(await coordinator.changePomodoro(.durations(work: 40, rest: nil)) == false)
    }

    @Test func finishedWorkIsRecordedWithTheCurrentTask() async throws {
        let task = try store.addTask("Write the focus view", project: "hilo-app", status: .doing, now: 9_000)
        _ = await coordinator.changePomodoro(.toggle)
        clock.set(10_000 + 25 * 60 + 1)
        await coordinator.tickPomodoro()
        #expect(await coordinator.focus?.phase == .rest)
        #expect(try store.focusCycles(task: task.id) == 1)
        #expect(try store.focusCycles(since: 0) == (1, 25))
    }

    @Test func newerBuddyStateWinsAndOlderGetsTheMacsBack() async throws {
        let newer = #"{"state":"paused","phase":"work","left_s":600,"work_min":30,"break_min":5,"cycle":2,"updated_at":10500}"#
        try await coordinator.handleBuddy(buddyMessage("device.pomodoro", newer))
        #expect(await coordinator.focus?.leftS == 600)
        #expect(await link.raw.isEmpty)
        let older = #"{"state":"stopped","phase":"work","work_min":25,"break_min":5,"cycle":0,"updated_at":9000}"#
        try await coordinator.handleBuddy(buddyMessage("device.pomodoro", older))
        guard case .pomodoro(let back) = await link.decoded().last else { Issue.record("no reply"); return }
        #expect(back.updatedAt == 10500 && back.cycle == 2)
    }

    private func restarted() -> Coordinator {
        Coordinator(host: "work", mapper: HookMapper(repoRoot: { _ in nil }), link: link, presence: DeskAway(),
                    clock: clock, recorder: StoreRecorder(store: store))
    }

    @Test func aRestartMidCycleNeitherLosesNorRepeatsCycles() async throws {
        _ = await coordinator.changePomodoro(.toggle)
        clock.set(10_000 + 25 * 60 + 1)
        await coordinator.tickPomodoro()
        #expect(try store.focusCycles(since: 0).count == 1)

        clock.set(10_000 + (25 + 5 + 25) * 60 + 1)
        let second = restarted()
        #expect(await second.focus?.cycle == 1)
        await second.tickPomodoro()
        let after = await second.focus
        #expect(after?.cycle == 2 && after?.phase == .rest)
        #expect(try store.focusCycles(since: 0).count == 2)

        let third = restarted()
        await third.tickPomodoro()
        await third.tickPomodoro()
        #expect(try store.focusCycles(since: 0).count == 2)
        await third.sendSnapshot()
        guard case .snapshot(let snap) = await link.decoded().last else { Issue.record("no snapshot"); return }
        #expect(snap.pomodoro?.cycle == 2)
    }

    @Test func theBuddyEchoingTheSameStateAfterARestartAddsNothing() async throws {
        _ = await coordinator.changePomodoro(.toggle)
        clock.set(10_000 + 25 * 60 + 1)
        await coordinator.tickPomodoro()
        let mine = try #require(await coordinator.focus)
        let second = restarted()
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let echo = String(decoding: try encoder.encode(mine), as: UTF8.self)
        try await second.handleBuddy(buddyMessage("device.pomodoro", echo))
        #expect(await second.focus == mine)
        #expect(try store.focusCycles(since: 0).count == 1)
    }

    @Test func aFreshStoreStartsWithoutAFocusState() async throws {
        #expect(await coordinator.focus == nil)
        await coordinator.sendSnapshot()
        guard case .snapshot(let snap) = await link.decoded().last else { Issue.record("no snapshot"); return }
        #expect(snap.pomodoro == nil)
    }

    @Test func pomodoroOpParsesCommands() async throws {
        #expect(ControlOps.pomodoroCommand(Data(#"{"action":"toggle"}"#.utf8)) == .toggle)
        #expect(ControlOps.pomodoroCommand(Data(#"{"action":"durations","work_min":50}"#.utf8)) == .durations(work: 50, rest: nil))
        #expect(ControlOps.pomodoroCommand(Data(#"{"action":"durations"}"#.utf8)) == nil)
        #expect(ControlOps.pomodoroCommand(Data(#"{"action":"skip"}"#.utf8)) == nil)
        let ops = ControlOps(coordinator: coordinator, buddy: nil, configPath: "/nonexistent/config.json", tokensFromTranscripts: false)
        let reply = try #require(await ops.handle(op: "pomodoro", body: Data(#"{"action":"toggle"}"#.utf8)))
        #expect(try JSONDecoder().decode(DaemonStatus.self, from: reply).pomodoro?.state == .running)
    }
}

final class FakePlayer: MediaPlayer, @unchecked Sendable {
    private let lock = NSLock()
    private var actions: [MediaAction] = []
    var now: Media?
    func current() -> Media? { lock.withLock { now } }
    func control(_ action: MediaAction) { lock.withLock { actions.append(action) } }
    var received: [MediaAction] { lock.withLock { actions } }
}

@Suite struct MediaFlowTests {
    let link = DeskLink()
    let clock = DeskClock(10_000)
    let coordinator: Coordinator

    init() {
        coordinator = Coordinator(host: "work", mapper: HookMapper(repoRoot: { _ in nil }), link: link, presence: DeskAway(), clock: clock)
    }

    @Test func parsesBothAppsAndClipsLongFields() {
        let spotify = AppleScriptPlayer.parse("Low Tide\tThe Pixels\t214000\t61\tplaying", durationDivisor: 1000)
        #expect(spotify == Media(title: "Low Tide", artist: "The Pixels", lengthS: 214, positionS: 61, playing: true))
        let music = AppleScriptPlayer.parse("Fan Noise\t\t180\t200\tpaused", durationDivisor: 1)
        #expect(music == Media(title: "Fan Noise", artist: "", lengthS: 180, positionS: 180, playing: false))
        #expect(AppleScriptPlayer.parse("", durationDivisor: 1) == nil)
        #expect(AppleScriptPlayer.parse("\tx\t1\t1\tplaying", durationDivisor: 1) == nil)
        #expect(AppleScriptPlayer.parse(String(repeating: "a", count: 200) + "\tb\t10\t1\tplaying", durationDivisor: 1)?.title.count == 80)
    }

    @Test func sendsOnlyChangesThatTheBuddyCannotExtrapolate() async {
        let song = Media(title: "Low Tide", artist: "The Pixels", lengthS: 214, positionS: 10, playing: true)
        await coordinator.updateMedia(song)
        clock.set(10_030)
        await coordinator.updateMedia(Media(title: "Low Tide", artist: "The Pixels", lengthS: 214, positionS: 41, playing: true))
        #expect(await link.types() == ["media.now_playing"])
        await coordinator.updateMedia(Media(title: "Low Tide", artist: "The Pixels", lengthS: 214, positionS: 120, playing: true))
        await coordinator.updateMedia(Media(title: "Low Tide", artist: "The Pixels", lengthS: 214, positionS: 120, playing: false))
        #expect(await link.types().count == 3)
        await coordinator.updateMedia(nil)
        guard case .snapshot(let snap) = await link.decoded().last else { Issue.record("no snapshot"); return }
        #expect(snap.media == nil)
        await coordinator.updateMedia(nil)
        #expect(await link.types().count == 4)
    }

    @Test func buddyControlsReachThePlayer() async throws {
        let player = FakePlayer()
        await coordinator.setPlayer(player)
        try await coordinator.handleBuddy(buddyMessage("media.control", #"{"action":"next"}"#))
        try await coordinator.handleBuddy(buddyMessage("media.control", #"{"action":"play_pause"}"#))
        try await until { player.received.count == 2 }
        #expect(player.received == [.next, .playPause])
    }
}

func until(_ condition: @Sendable () async -> Bool, timeout: Double = 2) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while await !condition() {
        guard Date() < deadline else { Issue.record("timed out"); return }
        try await Task.sleep(for: .milliseconds(5))
    }
}

final class ScriptedApps: @unchecked Sendable {
    private let lock = NSLock()
    private var runningIds: Set<String> = []
    private var replies: [String: (String?, Int?)] = [:]
    private var scripts: [String] = []
    private var t = 0
    private var logs: [String] = []

    func open(_ id: String, reply: (String?, Int?)) { lock.withLock { runningIds.insert(id); replies[id] = reply } }
    func quit(_ id: String) { lock.withLock { _ = runningIds.remove(id) } }
    func advance(_ seconds: Int) { lock.withLock { t += seconds } }
    var ran: [String] { lock.withLock { scripts } }
    var logged: [String] { lock.withLock { logs } }

    func player() -> AppleScriptPlayer {
        AppleScriptPlayer(
            log: { line in self.lock.withLock { self.logs.append(line) } },
            isRunning: { id in self.lock.withLock { self.runningIds.contains(id) } },
            script: { source in
                self.lock.withLock {
                    self.scripts.append(source)
                    guard let id = self.replies.keys.first(where: { source.contains("\"\($0)\"") }) else { return (nil, -1728) }
                    return self.runningIds.contains(id) ? self.replies[id]! : (nil, -600)
                }
            },
            now: { self.lock.withLock { self.t } })
    }
}

@Suite struct AppleScriptPlayerTests {
    let spotify = "com.spotify.client", music = "com.apple.Music"
    let apps = ScriptedApps()

    @Test func noPlayerOpenRunsNoScriptAndShowsNothing() {
        let player = apps.player()
        #expect(player.current() == nil)
        player.control(.playPause)
        #expect(apps.ran.isEmpty)
    }

    @Test func aPlayingAppWinsOverAPausedOneAndGetsTheControls() {
        apps.open(spotify, reply: ("Low Tide\tThe Pixels\t214000\t61\tpaused", nil))
        apps.open(music, reply: ("Fan Noise\tTabstop\t180\t20\tplaying", nil))
        let player = apps.player()
        #expect(player.current()?.title == "Fan Noise")
        player.control(.next)
        #expect(apps.ran.last == "with timeout of 5 seconds\ntell application id \"\(music)\" to next track\nend timeout")
        #expect(apps.ran.allSatisfy { $0.hasPrefix("with timeout of 5 seconds\n") })
    }

    @Test func aDeniedAppIsSkippedLoggedOnceAndRetriedLater() {
        apps.open(spotify, reply: (nil, -1743))
        apps.open(music, reply: ("Fan Noise\tTabstop\t180\t20\tplaying", nil))
        let player = apps.player()
        #expect(player.current()?.title == "Fan Noise")
        #expect(player.current()?.title == "Fan Noise")
        #expect(apps.ran.filter { $0.contains(spotify) }.count == 1)
        #expect(apps.logged.count == 1 && apps.logged[0].contains("denied"))

        apps.advance(AppleScriptPlayer.retryDeniedAfter)
        _ = player.current()
        #expect(apps.ran.filter { $0.contains(spotify) }.count == 2)
        #expect(apps.logged.count == 1)

        apps.open(spotify, reply: ("Low Tide\tThe Pixels\t214000\t61\tplaying", nil))
        apps.advance(AppleScriptPlayer.retryDeniedAfter)
        #expect(player.current()?.title == "Low Tide")
        #expect(apps.logged.last?.contains("allowed") == true)
    }

    @Test func anAppQuittingMidwayClearsTheMediaAndIgnoresControls() {
        apps.open(spotify, reply: ("Low Tide\tThe Pixels\t214000\t61\tplaying", nil))
        let player = apps.player()
        #expect(player.current() != nil)
        apps.quit(spotify)
        player.control(.playPause)
        #expect(!apps.ran.contains { $0.contains("playpause") })
        #expect(player.current() == nil)

        apps.open(spotify, reply: ("Low Tide\tThe Pixels\t214000\t61\tplaying", nil))
        _ = player.current()
        apps.quit(spotify)
        apps.open(spotify, reply: (nil, -600))
        #expect(player.current() == nil)
    }

    @Test func aSlowPlayerDoesNotHoldUpTheDaemon() async throws {
        let gate = DispatchSemaphore(value: 0), entered = Flag()
        let slow = SlowPlayer(gate: gate, entered: entered)
        let coordinator = Coordinator(host: "work", mapper: HookMapper(repoRoot: { _ in nil }), link: DeskLink(), presence: DeskAway(),
                                      clock: DeskClock(10_000))
        await coordinator.setPlayer(slow)
        let poll = Task { await coordinator.pollMedia() }
        try await until { entered.isSet }
        let answered = Flag()
        Task { _ = await coordinator.currentHost; answered.set() }
        try await until { answered.isSet }
        let blocked = !answered.isSet
        gate.signal()
        gate.signal()
        await poll.value
        #expect(!blocked)
        try await coordinator.handleBuddy(buddyMessage("media.control", #"{"action":"next"}"#))
    }
}

final class SlowPlayer: MediaPlayer, @unchecked Sendable {
    let gate: DispatchSemaphore, entered: Flag
    init(gate: DispatchSemaphore, entered: Flag) { self.gate = gate; self.entered = entered }
    func current() -> Media? {
        entered.set()
        gate.wait()
        return nil
    }
    func control(_ action: MediaAction) {}
}

final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func set() { lock.withLock { value = true } }
    var isSet: Bool { lock.withLock { value } }
}
