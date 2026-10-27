import Foundation
import Testing
import HiloContract
@testable import HiloCore

private func permission(_ session: String, id: String = ULID.make(), diff: Int = 0) -> PermissionRequest {
    PermissionRequest(requestId: id, session: session, project: "p-\(session)", tool: "Edit",
                      detail: String(repeating: "d", count: 300), why: String(repeating: "w", count: 300),
                      diff: diff > 0 ? Array(repeating: DiffLine(.added, String(repeating: "x", count: 120)), count: diff) : nil,
                      cwd: "/home/dev/code/p", risk: .low, remoteAllowed: true, expiresAt: 2_000)
}

@Test func lifecycleTracksStatusAndPending() throws {
    var store = SessionStore()
    store.apply(.sessionStart(SessionStart(session: "s1", project: "api", task: "Refactor")), now: 10)
    let p = permission("s1")
    store.apply(.needsPermission(p), now: 20)
    store.apply(.agentStep(AgentStep(session: "s1", kind: .read, text: "Read a")), now: 25)
    var s = try #require(store.snapshot().sessions.first)
    #expect(s.status == .waiting)
    #expect(s.pendingPermission == p)
    #expect(s.since == 20)

    store.apply(.requestResolved(RequestResolved(requestId: p.requestId, session: "s1", kind: .permission, outcome: .approved, via: .buddy)), now: 30)
    store.apply(.taskDone(TaskDone(session: "s1", summary: "Done")), now: 40)
    s = try #require(store.snapshot().sessions.first)
    #expect(s.status == .done)
    #expect(s.pendingPermission == nil)
    #expect(s.summary == "Done")

    store.apply(.sessionEnd(SessionRef(session: "s1")), now: 50)
    #expect(store.snapshot().sessions.isEmpty)
}

@Test func keepsLastFiveSteps() throws {
    var store = SessionStore()
    store.apply(.sessionStart(SessionStart(session: "s1", project: "api", task: "")), now: 0)
    for i in 1...7 { store.apply(.agentStep(AgentStep(session: "s1", kind: .run, text: "step \(i)")), now: i) }
    #expect(store.snapshot().sessions.first?.steps?.map(\.text) == (3...7).map { "step \($0)" })
}

@Test func ordersByPriorityAndCapsAtEight() {
    var store = SessionStore()
    for i in 0..<10 { store.apply(.sessionStart(SessionStart(session: "s\(i)", project: "p", task: "")), now: i) }
    store.apply(.taskDone(TaskDone(session: "s9", summary: "ok")), now: 20)
    store.apply(.needsPermission(permission("s0")), now: 21)
    let ids = store.snapshot().sessions.map(\.session)
    #expect(ids.count == 8)
    #expect(ids.first == "s0")
    #expect(!ids.contains("s9"))
}

@Test func worstCaseSnapshotIsTrimmedToFitAndStaysValid() throws {
    var store = SessionStore()
    for i in 0..<8 {
        store.apply(.sessionStart(SessionStart(session: "s\(i)", project: "p\(i)", task: String(repeating: "t", count: 120))), now: i)
        for _ in 0..<5 { store.apply(.agentStep(AgentStep(session: "s\(i)", kind: .edit, text: String(repeating: "e", count: 120))), now: i) }
        store.apply(.needsPermission(permission("s\(i)", diff: 12)), now: 100 + i)
    }
    let snap = store.snapshot()
    let bytes = try Wire.encode(.snapshot(snap), host: "work")
    #expect(bytes.count <= Framing.maxMessageSize)
    #expect(snap.sessions.count == 8)
    #expect(snap.sessions.allSatisfy { $0.pendingPermission != nil })
    _ = try Wire.decodeOutbound(bytes)
}

@Test func aHandBackKeepsTheSessionWaitingOnTheMacUntilItsNextStep() throws {
    var store = SessionStore()
    store.apply(.sessionStart(SessionStart(session: "s1", project: "api", task: "")), now: 10)
    let p = permission("s1")
    store.apply(.needsPermission(p), now: 20)
    store.apply(.requestResolved(RequestResolved(requestId: p.requestId, session: "s1", kind: .permission, outcome: .expired, via: .timeout)), now: 30)
    var s = try #require(store.snapshot().sessions.first)
    #expect(s.status == .waiting)
    #expect(s.pendingPermission == nil)
    #expect(s.since == 20)

    store.apply(.agentStep(AgentStep(session: "s1", kind: .run, text: "npm test")), now: 40)
    s = try #require(store.snapshot().sessions.first)
    #expect(s.status == .working)
    #expect(s.since == 40)
}
