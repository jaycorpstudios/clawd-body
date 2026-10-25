import Foundation
import Testing
import HiloContract
import HiloCore
@testable import HiloRuntime

private actor FakeWriter: FrameWriter {
    var frames: [Data] = []
    var failAfter = Int.max
    var delay = false

    func setFailAfter(_ n: Int) { failAfter = n }
    func setDelay(_ on: Bool) { delay = on }

    func write(_ frame: Data) async -> Bool {
        if delay { for _ in 0..<5 { await Task.yield() } }
        guard frames.count < failAfter else { return false }
        frames.append(frame)
        return true
    }

    func messages() -> [Data] {
        var r = Framing.Reassembler()
        return frames.compactMap { r.push($0) }
    }
}

private actor Inbox {
    var messages: [Data] = []
    var ups = 0
    func add(_ m: Data) { messages.append(m) }
    func up() { ups += 1 }
}

private func session(_ writer: FakeWriter, _ inbox: Inbox) async -> BuddySession {
    let s = BuddySession(writer: writer)
    await s.setHandlers(onUp: { await inbox.up() }, onMessage: { await inbox.add($0) })
    return s
}

private func message(_ n: Int, _ fill: UInt8) -> Data { Data(repeating: fill, count: n) }

@Test func sendsNothingWhileTheLinkIsDown() async {
    let w = FakeWriter(), inbox = Inbox()
    let s = await session(w, inbox)
    await s.send(message(10, 1))
    #expect(await w.frames.isEmpty)
}

@Test func linkUpRunsTheHandlerAndFramesToTheNegotiatedSize() async {
    let w = FakeWriter(), inbox = Inbox()
    let s = await session(w, inbox)
    await s.handle(.up(frameSize: 40))
    #expect(await inbox.ups == 1)
    await s.send(message(100, 1))
    await s.send(message(10, 2))
    let frames = await w.frames
    #expect(frames.allSatisfy { $0.count <= 40 })
    #expect(frames.first?[0] != frames.last?[0])
    #expect(await w.messages() == [message(100, 1), message(10, 2)])
}

@Test func concurrentSendsNeverInterleaveFrames() async {
    let w = FakeWriter(), inbox = Inbox()
    await w.setDelay(true)
    let s = await session(w, inbox)
    await s.handle(.up(frameSize: 40))
    await withTaskGroup(of: Void.self) { group in
        for i in 0..<6 { group.addTask { await s.send(message(120, UInt8(i))) } }
    }
    let received = await w.messages()
    #expect(received.count == 6)
    #expect(Set(received.map { $0[0] }) == Set(0..<6))
}

@Test func failedWriteAbandonsOnlyThatMessage() async {
    let w = FakeWriter(), inbox = Inbox()
    let s = await session(w, inbox)
    await s.handle(.up(frameSize: 40))
    await w.setFailAfter(1)
    await s.send(message(100, 1))
    #expect(await w.frames.count == 1)
    await w.setFailAfter(.max)
    await s.send(message(10, 2))
    #expect(await w.messages() == [message(10, 2)])
}

@Test func incomingFramesAreReassembledAndLinkDownDropsAPartialOne() async throws {
    let w = FakeWriter(), inbox = Inbox()
    let s = await session(w, inbox)
    await s.handle(.up(frameSize: 40))
    let partial = try Framing.frames(message(100, 3), seq: 0, frameSize: 40)
    await s.handle(.frame(partial[0]))
    await s.handle(.down)
    await s.handle(.up(frameSize: 40))
    await s.handle(.frame(partial[1]))
    await s.handle(.frame(partial[2]))
    for f in try Framing.frames(message(50, 4), seq: 1, frameSize: 40) { await s.handle(.frame(f)) }
    #expect(await inbox.messages == [message(50, 4)])
    #expect(await inbox.ups == 2)
}

@Test func linkUpSendsTheCoordinatorSnapshot() async throws {
    let w = FakeWriter(), inbox = Inbox()
    let s = BuddySession(writer: w)
    let coordinator = Coordinator(host: "work", mapper: HookMapper(repoRoot: { _ in nil }), link: s,
                                  presence: NeverPresent())
    await s.setHandlers(onUp: { await coordinator.sendSnapshot() }, onMessage: { await inbox.add($0) })
    await s.handle(.up(frameSize: 185))
    let sent = try #require(await w.messages().first)
    guard case .snapshot = try Wire.decodeOutbound(sent).body else { Issue.record("not a snapshot"); return }
}

private struct NeverPresent: PresenceProbe {
    func userIsPresent() -> Bool { false }
}
