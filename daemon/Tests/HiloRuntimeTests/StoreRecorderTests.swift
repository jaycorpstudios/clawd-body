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
