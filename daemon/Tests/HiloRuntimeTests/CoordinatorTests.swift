import Foundation
import Testing
import HiloContract
import HiloCore
@testable import HiloRuntime

private let repo = "/home/dev/code/payments-api"

private final class Box<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: T
    init(_ value: T) { self.value = value }
    func get() -> T { lock.withLock { value } }
    func set(_ v: T) { lock.withLock { value = v } }
}

private struct FakeClock: Clock {
    let time = Box(1_000)
    func now() -> Int { time.get() }
    func sleep(seconds: Double) async { await Task.yield() }
}

private struct FakePresence: PresenceProbe {
    let present = Box(false)
    let polls = Box(0)
    func userIsPresent() -> Bool { polls.set(polls.get() + 1); return present.get() }
}

private actor RecordingLink: BuddyLink {
    var raw: [Data] = []
    func send(_ data: Data) async { raw.append(data) }
    private var messages: [[String: Any]] { raw.compactMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } }
    func types() -> [String] { messages.compactMap { $0["type"] as? String } }
    func lastData(_ type: String) -> Data? {
        (messages.last { $0["type"] as? String == type }?["data"]).flatMap { try? JSONSerialization.data(withJSONObject: $0) }
    }
    func field(_ type: String, _ key: String) -> String? {
        let data = messages.last { $0["type"] as? String == type }?["data"] as? [String: Any]
        return data?[key] as? String
    }
}

private struct Harness {
    let clock = FakeClock()
    let presence = FakePresence()
    let link = RecordingLink()
    let coordinator: Coordinator

    init() {
        coordinator = Coordinator(host: "work", mapper: HookMapper(repoRoot: { _ in repo }),
                                  link: link, presence: presence, clock: clock, pollSeconds: 0)
    }

    func permission(_ command: String) throws -> HookInput {
        try HookInput.decode(Data(#"""
        {"hook_event_name":"PermissionRequest","session_id":"s1","cwd":"\#(repo)","tool_name":"Bash","tool_input":{"command":"\#(command)"}}
        """#.utf8))
    }

    func pendingRequestId() async throws -> String {
        for _ in 0..<10_000 {
            if let id = await link.field("agent.needs_permission", "request_id") { return id }
            await Task.yield()
        }
        throw CancellationError()
    }

    func ack(_ id: String) async throws {
        let msg = #"{"v":1,"id":"\#(ULID.make())","ts":\#(clock.now()),"type":"device.ack","data":{"request_id":"\#(id)","seen":true}}"#
        try await coordinator.handleBuddy(Data(msg.utf8))
    }

    /// Waits until the watch loop has checked presence twice more.
    func settle() async {
        let target = presence.polls.get() + 2
        for _ in 0..<1_000_000 where presence.polls.get() < target { await Task.yield() }
    }

    func buddy(_ id: String, _ decision: String) async throws {
        let msg = #"{"v":1,"id":"\#(ULID.make())","ts":\#(clock.now()),"type":"permission.decision","data":{"request_id":"\#(id)","decision":"\#(decision)"}}"#
        try await coordinator.handleBuddy(Data(msg.utf8))
    }
}

private func behavior(_ reply: Data) -> String? {
    let json = try? JSONSerialization.jsonObject(with: reply) as? [String: Any]
    let decision = (json?["hookSpecificOutput"] as? [String: Any])?["decision"] as? [String: Any]
    return decision?["behavior"] as? String
}

@Test func presentUserGetsTheTerminalPromptAtOnce() async throws {
    let h = Harness()
    h.presence.present.set(true)
    let reply = await h.coordinator.handleHook(try h.permission("npm test"))
    #expect(reply.isEmpty)
    #expect(await h.link.types() == ["agent.step"])
}

@Test func aUserWhoGoesQuietWithinTheGraceGetsTheRequestOnTheBuddy() async throws {
    let h = Harness()
    h.presence.present.set(true)
    let hook = Task { await h.coordinator.handleHook(try h.permission("npm test")) }
    await Task.yield()
    h.presence.present.set(false)
    try await h.buddy(try await h.pendingRequestId(), "approve")
    #expect(behavior(try await hook.value) == "allow")
}

@Test func awayUserApprovesFromBuddy() async throws {
    let h = Harness()
    let hook = Task { await h.coordinator.handleHook(try h.permission("npm test")) }
    try await h.buddy(try await h.pendingRequestId(), "approve")
    #expect(behavior(try await hook.value) == "allow")
    #expect(await h.link.field("agent.request_resolved", "outcome") == "approved")
}

@Test func highRiskApprovalKeepsWaitingAndDenyIsHonored() async throws {
    let h = Harness()
    let hook = Task { await h.coordinator.handleHook(try h.permission("terraform apply")) }
    let id = try await h.pendingRequestId()
    try await h.buddy(id, "approve")
    #expect(await h.link.field("agent.request_resolved", "request_id") == nil)
    try await h.buddy(id, "deny")
    #expect(behavior(try await hook.value) == "deny")
}

@Test func returningToTheMacReleasesTheHook() async throws {
    let h = Harness()
    let hook = Task { await h.coordinator.handleHook(try h.permission("npm test")) }
    let id = try await h.pendingRequestId()
    h.presence.present.set(true)
    #expect(try await hook.value.isEmpty)
    #expect(await h.link.field("agent.request_resolved", "outcome") == "expired")
    try await h.buddy(id, "approve")
    #expect(await h.link.types().filter { $0 == "agent.request_resolved" }.count == 2)
}

@Test func aRequestOnTheBuddysScreenGoesBackOnlyAfter10sOfInputOnTheMac() async throws {
    let h = Harness()
    let hook = Task { await h.coordinator.handleHook(try h.permission("npm test")) }
    let id = try await h.pendingRequestId()
    try await h.ack(id)
    h.presence.present.set(true)
    await h.settle()
    h.presence.present.set(false)
    await h.settle()
    h.clock.time.set(1_000 + Coordinator.handBackAfter + 1)
    await h.settle()
    h.presence.present.set(true)
    await h.settle()
    #expect(await h.link.field("agent.request_resolved", "request_id") == nil)
    h.clock.time.set(1_000 + 2 * Coordinator.handBackAfter + 1)
    #expect(try await hook.value.isEmpty)
    #expect(await h.link.field("agent.request_resolved", "outcome") == "expired")
}

@Test func aSnapshotAfterAHandBackKeepsTheSessionWaitingWithNothingToAnswer() async throws {
    let h = Harness()
    let hook = Task { await h.coordinator.handleHook(try h.permission("npm test")) }
    _ = try await h.pendingRequestId()
    h.presence.present.set(true)
    _ = try await hook.value
    await h.coordinator.sendSnapshot()
    let raw = try #require(await h.link.raw.last)
    guard case .snapshot(let snap) = try Wire.decodeOutbound(raw).body else { Issue.record("not a snapshot"); return }
    let s = try #require(snap.sessions.first)
    #expect(s.status == .waiting)
    #expect(s.pendingPermission == nil && s.pendingQuestion == nil)
}

@Test func expiryReleasesTheHook() async throws {
    let h = Harness()
    let hook = Task { await h.coordinator.handleHook(try h.permission("npm test")) }
    _ = try await h.pendingRequestId()
    h.clock.time.set(1_000 + HookMapper.expirySeconds)
    #expect(try await hook.value.isEmpty)
    #expect(await h.link.field("agent.request_resolved", "via") == "timeout")
}

@Test func everyEmittedMessageIsValidContract() async throws {
    let h = Harness()
    let hook = Task { await h.coordinator.handleHook(try h.permission("npm test")) }
    try await h.buddy(try await h.pendingRequestId(), "approve")
    _ = try await hook.value
    for bytes in await h.link.raw {
        #expect(throws: Never.self) { try Wire.decodeOutbound(bytes) }
    }
}

@Test func snapshotCarriesHeldRequest() async throws {
    let h = Harness()
    let hook = Task { await h.coordinator.handleHook(try h.permission("npm test")) }
    let id = try await h.pendingRequestId()
    await h.coordinator.sendSnapshot()
    let snapshot = try #require(await h.link.raw.last)
    guard case .snapshot(let snap) = try Wire.decodeOutbound(snapshot).body else { Issue.record("not a snapshot"); return }
    #expect(snap.sessions.first?.pendingPermission?.requestId == id)
    try await h.buddy(id, "deny")
    _ = try await hook.value
}

@Suite struct CoordinatorUsageTests {
    @Test func statusLineLimitsReachTheBuddyAndTheSnapshot() async throws {
        let h = Harness()
        let resets = h.clock.now() + 3_600
        await h.coordinator.updateUsage(RateLimits(fiveHour: .init(usedPercentage: 42, resetsAt: resets)))
        await h.coordinator.updateUsage(RateLimits(fiveHour: .init(usedPercentage: 42, resetsAt: resets)))
        await h.coordinator.updateUsage(tokensToday: 5_000)
        #expect(await h.link.types() == ["usage.update", "usage.update"])
        await h.coordinator.sendSnapshot()
        let raw = try #require(await h.link.lastData("snapshot"))
        let snapshot = try #require(try JSONSerialization.jsonObject(with: raw) as? [String: Any])
        let usage = try #require(snapshot["usage"] as? [String: Any])
        #expect(usage["session_pct"] as? Double == 42)
        #expect(usage["reset_in_min"] as? Int == 60)
        #expect(usage["tokens_today"] as? Int == 5_000)
    }
}

@Suite struct CoordinatorPhase4Tests {
    private func question() throws -> HookInput {
        try HookInput.decode(Data(#"""
        {"hook_event_name":"PreToolUse","session_id":"s1","cwd":"\#(repo)","tool_name":"AskUserQuestion",
         "tool_input":{"questions":[{"question":"Where should I store history?","header":"Storage","multiSelect":false,
           "options":[{"label":"Local SQLite","description":"One file"},{"label":"Markdown files","description":"Plain text"}]}]}}
        """#.utf8))
    }

    private func questionId(_ h: Harness) async throws -> String {
        for _ in 0..<10_000 {
            if let id = await h.link.field("agent.question", "request_id") { return id }
            await Task.yield()
        }
        throw CancellationError()
    }

    private func answer(_ h: Harness, _ id: String, index: Int, choice: String) async throws {
        let msg = #"{"v":1,"id":"\#(ULID.make())","ts":\#(h.clock.now()),"type":"question.answer","data":{"request_id":"\#(id)","choice_index":\#(index),"choice":"\#(choice)"}}"#
        try await h.coordinator.handleBuddy(Data(msg.utf8))
    }

    private func resolvedCount(_ h: Harness) async -> Int {
        await h.link.types().filter { $0 == "agent.request_resolved" }.count
    }

    @Test func lowRiskDenyFromTheBuddyDeniesTheHook() async throws {
        let h = Harness()
        let hook = Task { await h.coordinator.handleHook(try h.permission("npm test")) }
        try await h.buddy(try await h.pendingRequestId(), "deny")
        #expect(behavior(try await hook.value) == "deny")
        #expect(await h.link.field("agent.request_resolved", "outcome") == "denied")
        #expect(await h.link.field("agent.request_resolved", "via") == "buddy")
    }

    @Test func aDecisionIsSingleUse() async throws {
        let h = Harness()
        let hook = Task { await h.coordinator.handleHook(try h.permission("npm test")) }
        let id = try await h.pendingRequestId()
        try await h.buddy(id, "deny")
        try await h.buddy(id, "approve")
        #expect(behavior(try await hook.value) == "deny")
        #expect(await resolvedCount(h) == 2)
        #expect(await h.link.field("agent.request_resolved", "outcome") == "denied")
    }

    @Test func answeredQuestionEchoesTheInputWithTheAnswer() async throws {
        let h = Harness()
        let hook = Task { await h.coordinator.handleHook(try question()) }
        try await answer(h, try await questionId(h), index: 1, choice: "Markdown files")
        let out = try #require(try JSONSerialization.jsonObject(with: try await hook.value) as? [String: Any])
        let specific = try #require(out["hookSpecificOutput"] as? [String: Any])
        #expect(specific["hookEventName"] as? String == "PreToolUse")
        #expect(specific["permissionDecision"] as? String == "allow")
        let updated = try #require(specific["updatedInput"] as? [String: Any])
        #expect(updated["answers"] as? [String: String] == ["Where should I store history?": "Markdown files"])
        let questions = try #require(updated["questions"] as? [[String: Any]])
        #expect(questions.first?["header"] as? String == "Storage")
        #expect(await h.link.field("agent.request_resolved", "outcome") == "answered")
    }

    @Test func answerThatDoesNotMatchTheOptionsKeepsWaiting() async throws {
        let h = Harness()
        let hook = Task { await h.coordinator.handleHook(try question()) }
        let id = try await questionId(h)
        try await answer(h, id, index: 1, choice: "Local SQLite")
        await #expect(throws: ContractError.self) { try await answer(h, id, index: 5, choice: "Markdown files") }
        #expect(await resolvedCount(h) == 0)
        try await answer(h, id, index: 0, choice: "Local SQLite")
        #expect(try await hook.value.isEmpty == false)
    }

    @Test func expiredQuestionFallsBackToTheTerminal() async throws {
        let h = Harness()
        let hook = Task { await h.coordinator.handleHook(try question()) }
        let id = try await questionId(h)
        h.clock.time.set(1_000 + HookMapper.expirySeconds)
        #expect(try await hook.value.isEmpty)
        #expect(await h.link.field("agent.request_resolved", "outcome") == "expired")
        try await answer(h, id, index: 0, choice: "Local SQLite")
        #expect(await resolvedCount(h) == 2)
    }

    @Test func requestIsStillHeldOneSecondBeforeExpiry() async throws {
        let h = Harness()
        let hook = Task { await h.coordinator.handleHook(try h.permission("npm test")) }
        let id = try await h.pendingRequestId()
        h.clock.time.set(1_000 + HookMapper.expirySeconds - 1)
        for _ in 0..<200 { await Task.yield() }
        #expect(await resolvedCount(h) == 0)
        try await h.buddy(id, "approve")
        #expect(behavior(try await hook.value) == "allow")
    }
}

@Test func aSessionWithNoHookFor10MinGoesIdleOnTheBuddy() async throws {
    let h = Harness()
    _ = await h.coordinator.handleHook(try HookInput.decode(Data(#"{"hook_event_name":"SessionStart","session_id":"s1","cwd":"\#(repo)"}"#.utf8)))
    h.clock.time.set(1_599)
    await h.coordinator.tickSessions()
    #expect(!(await h.link.types()).contains("snapshot"))
    h.clock.time.set(1_600)
    await h.coordinator.tickSessions()
    let snap = try JSONSerialization.jsonObject(with: try #require(await h.link.lastData("snapshot"))) as? [String: Any]
    #expect(((snap?["sessions"] as? [[String: Any]])?.first?["status"] as? String) == "idle")
}

@Test func buddyMessagesOutsideThe120sWindowOrSeenBeforeAreDropped() async throws {
    let h = Harness()
    func battery(_ id: String, ts: Int) -> Data {
        Data(#"{"v":1,"id":"\#(id)","ts":\#(ts),"type":"device.battery","data":{"pct":50,"charging":false}}"#.utf8)
    }
    try await h.coordinator.handleBuddy(battery(ULID.make(), ts: 1_000 - 120))
    try await h.coordinator.handleBuddy(battery(ULID.make(), ts: 1_000 + 120))
    await #expect(throws: ContractError.self) { try await h.coordinator.handleBuddy(battery(ULID.make(), ts: 1_000 - 121)) }
    await #expect(throws: ContractError.self) { try await h.coordinator.handleBuddy(battery(ULID.make(), ts: 1_000 + 121)) }
    let id = ULID.make()
    try await h.coordinator.handleBuddy(battery(id, ts: 1_000))
    await #expect(throws: ContractError.replayed("id \(id) already seen")) { try await h.coordinator.handleBuddy(battery(id, ts: 1_000)) }
}
