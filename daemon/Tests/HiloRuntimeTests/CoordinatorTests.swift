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
    func userIsPresent() -> Bool { present.get() }
}

private actor RecordingLink: BuddyLink {
    var raw: [Data] = []
    func send(_ data: Data) async { raw.append(data) }
    private var messages: [[String: Any]] { raw.compactMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } }
    func types() -> [String] { messages.compactMap { $0["type"] as? String } }
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

    func buddy(_ id: String, _ decision: String) async throws {
        let msg = #"{"v":1,"id":"\#(ULID.make())","ts":1000,"type":"permission.decision","data":{"request_id":"\#(id)","decision":"\#(decision)"}}"#
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
