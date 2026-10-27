import Foundation
import Testing
import HiloContract
import HiloCore
import HiloStore
@testable import HiloRuntime

private actor Sink: BuddyLink {
    var raw: [Data] = []
    func send(_ data: Data) async { raw.append(data) }
    func lastSnapshot() -> Data? {
        raw.last { (try? JSONSerialization.jsonObject(with: $0) as? [String: Any])?["type"] as? String == "snapshot" }
    }
}

private struct Away: PresenceProbe { func userIsPresent() -> Bool { false } }

private func makeStore() throws -> HiloStore {
    let path = FileManager.default.temporaryDirectory.appending(path: "hilo-rec-\(UUID().uuidString).sqlite")
    return try HiloStore(path: path.path(percentEncoded: false))
}

@Test func messagesSentToTheBuddyAreRecorded() async throws {
    let store = try makeStore()
    let link = Sink()
    let coordinator = Coordinator(host: "work", mapper: HookMapper(repoRoot: { _ in "/home/dev/code/api" }), link: link,
                                  presence: Away(), recorder: StoreRecorder(store: store))
    let start = try HookInput.decode(Data(#"{"hook_event_name":"SessionStart","session_id":"s1","cwd":"/home/dev/code/api"}"#.utf8))
    _ = await coordinator.handleHook(start)
    let step = try HookInput.decode(Data(#"""
    {"hook_event_name":"PostToolUse","session_id":"s1","cwd":"/home/dev/code/api","tool_name":"Read","tool_input":{"file_path":"/home/dev/code/api/a.ts"}}
    """#.utf8))
    _ = await coordinator.handleHook(step)

    let s = try #require(try store.sessions(since: 0).first)
    #expect(s.id == "s1" && s.project?.name == "api")
    #expect(try store.steps(session: "s1").count == 1)
    #expect(try store.sessionRepos(since: 0).map(\.repo) == ["/home/dev/code/api"])
    #expect(try store.activeSeconds(since: 0).keys.contains("api"))
}

@Test func snapshotCarriesTheCurrentHiloTask() async throws {
    let store = try makeStore()
    try store.addTask("Ship the app", project: "hilo", status: .doing, now: 1)
    try store.addTask("Write docs", project: nil, now: 2)
    let link = Sink()
    let coordinator = Coordinator(host: "work", mapper: HookMapper(repoRoot: { _ in nil }), link: link,
                                  presence: Away(), recorder: StoreRecorder(store: store))
    await coordinator.sendSnapshot()
    let raw = try #require(await link.lastSnapshot())
    let json = try #require(try JSONSerialization.jsonObject(with: raw) as? [String: Any])
    let hilo = try #require((json["data"] as? [String: Any])?["hilo"] as? [String: Any])
    #expect((hilo["current"] as? [String: Any])?["title"] as? String == "Ship the app")
    #expect(((hilo["next"] as? [[String: Any]])?.first)?["project"] as? String == "inbox")
}

@Test func sessionsSeenMidwayGetTheirProjectFromTheHook() async throws {
    let store = try makeStore()
    let coordinator = Coordinator(host: "work", mapper: HookMapper(repoRoot: { _ in "/home/dev/code/api" }), link: Sink(),
                                  presence: Away(), recorder: StoreRecorder(store: store))
    let prompt = try HookInput.decode(Data(#"{"hook_event_name":"UserPromptSubmit","session_id":"s9","cwd":"/home/dev/code/api"}"#.utf8))
    _ = await coordinator.handleHook(prompt)
    #expect(try store.sessions(since: 0).first?.project?.name == "api")
}

@Test func sessionsGetALookThatSurvivesTheirEndAndCanBeChanged() async throws {
    let store = try makeStore()
    let link = Sink()
    let coordinator = Coordinator(host: "work", mapper: HookMapper(repoRoot: { _ in "/home/dev/code/api" }), link: link,
                                  presence: Away(), recorder: StoreRecorder(store: store))
    let ops = ControlOps(coordinator: coordinator, buddy: nil, configPath: "/nonexistent/config.json", tokensFromTranscripts: false)
    for id in ["s1", "s2"] {
        _ = await coordinator.handleHook(try HookInput.decode(Data(#"{"hook_event_name":"SessionStart","session_id":"\#(id)","cwd":"/home/dev/code/api"}"#.utf8)))
    }
    let base = PetLook.of(project: "api")
    let s1 = try #require(try store.look(session: "s1")), s2 = try #require(try store.look(session: "s2"))
    #expect(s1 == SessionLook(hue: base.hue, acc: base.accessory))
    #expect(s2.acc != s1.acc && s2.hue != s1.hue)
    let started = await link.raw.compactMap { try? Wire.decodeOutbound($0).body }.compactMap { m -> SessionLook? in
        if case .sessionStart(let s) = m { return s.look } else { return nil }
    }
    #expect(started == [s1, s2])

    try await coordinator.handleBuddy(Data(#"{"v":1,"id":"\#(ULID.make())","ts":1000,"type":"device.session_look","data":{"session":"s2","acc":"crown"}}"#.utf8))
    #expect(try store.look(session: "s2") == SessionLook(hue: s2.hue, acc: .crown))
    let raw = try #require(await link.lastSnapshot())
    guard case .snapshot(let snap) = try Wire.decodeOutbound(raw).body else { Issue.record("no snapshot"); return }
    #expect(snap.sessions.first { $0.session == "s2" }?.look == SessionLook(hue: s2.hue, acc: .crown))
    #expect(try store.sessions(since: 0).first { $0.id == "s2" }?.look == SessionLook(hue: s2.hue, acc: .crown))

    let live = try JSONEncoder().encode(SessionLookChange(session: "s2", acc: .band))
    #expect(await ops.handle(op: "session-look", body: live).map { String(decoding: $0, as: UTF8.self).hasPrefix("rejected") } == false)
    let echoed = try #require(await link.lastSnapshot())
    guard case .snapshot(let next) = try Wire.decodeOutbound(echoed).body else { Issue.record("no snapshot"); return }
    #expect(next.sessions.first { $0.session == "s2" }?.look == SessionLook(hue: s2.hue, acc: .band))

    _ = await coordinator.handleHook(try HookInput.decode(Data(#"{"hook_event_name":"SessionEnd","session_id":"s1","cwd":"/home/dev/code/api"}"#.utf8)))
    let body = try JSONEncoder().encode(SessionLookChange(session: "s1", acc: .heart))
    #expect(await ops.handle(op: "session-look", body: body).map { String(decoding: $0, as: UTF8.self).hasPrefix("rejected") } == false)
    #expect(try store.look(session: "s1") == SessionLook(hue: s1.hue, acc: .heart))
    #expect(try store.sessions(since: 0).first { $0.id == "s1" }?.look?.acc == .heart)
    let unknown = try JSONEncoder().encode(SessionLookChange(session: "nope", acc: .heart))
    #expect(await ops.handle(op: "session-look", body: unknown).map { String(decoding: $0, as: UTF8.self).hasPrefix("rejected") } == true)

    _ = await coordinator.handleHook(try HookInput.decode(Data(#"{"hook_event_name":"SessionStart","session_id":"s1","cwd":"/home/dev/code/api"}"#.utf8)))
    #expect(try store.look(session: "s1")?.acc == .heart)
}

@Test func aNewPromptAfterTheTurnEndedMakesTheSessionWorkAgain() async throws {
    let store = try makeStore()
    let coordinator = Coordinator(host: "work", mapper: HookMapper(repoRoot: { _ in "/home/dev/code/api" }), link: Sink(),
                                  presence: Away(), recorder: StoreRecorder(store: store))
    func hook(_ json: String) async throws { _ = await coordinator.handleHook(try HookInput.decode(Data(json.utf8))) }
    try await hook(#"{"hook_event_name":"SessionStart","session_id":"s1","cwd":"/home/dev/code/api"}"#)
    try await hook(#"{"hook_event_name":"Stop","session_id":"s1","cwd":"/home/dev/code/api","last_assistant_message":"Done."}"#)
    #expect(try store.sessions(since: 0).first?.status == .done)
    try await hook(#"{"hook_event_name":"UserPromptSubmit","session_id":"s1","cwd":"/home/dev/code/api"}"#)
    #expect(try store.sessions(since: 0).first?.status == .working)
    try await hook(#"{"hook_event_name":"SessionEnd","session_id":"s1","cwd":"/home/dev/code/api"}"#)
    try await hook(#"{"hook_event_name":"UserPromptSubmit","session_id":"s1","cwd":"/home/dev/code/api"}"#)
    #expect(try store.sessions(since: 0).first?.status == .done)
}
