import Foundation
import Testing
import HiloCore
@testable import HiloRuntime

final class OpsFakeBuddy: BuddyControl, @unchecked Sendable {
    private let lock = NSLock()
    private var _state = BuddyStatus(link: .notPaired)
    private var _reconnects = 0
    var state: BuddyStatus { lock.withLock { _state } }
    var reconnects: Int { lock.withLock { _reconnects } }
    func status() -> BuddyStatus { state }
    func startPairing() -> Bool {
        lock.withLock {
            guard _state.link != .connected else { return false }
            _state.pairing = .scanning
            return true
        }
    }
    func cancelPairing() { lock.withLock { _state.pairing = .idle } }
    func reconnect() { lock.withLock { _reconnects += 1 } }
}

struct OpsNoLink: BuddyLink { func send(_ data: Data) async {} }
struct OpsPresent: PresenceProbe { func userIsPresent() -> Bool { true } }

@Suite struct ControlOpsTests {
    let path = FileManager.default.temporaryDirectory.appending(path: "hilo-ops-\(UUID().uuidString)/config.json")
        .path(percentEncoded: false)
    let buddy = OpsFakeBuddy()
    let coordinator = Coordinator(host: "work", mapper: HookMapper(repoRoot: { _ in nil }), link: OpsNoLink(), presence: OpsPresent())
    let ops: ControlOps

    init() {
        ops = ControlOps(coordinator: coordinator, buddy: buddy, configPath: path, tokensFromTranscripts: true)
    }

    func decode(_ data: Data?) throws -> DaemonStatus {
        try JSONDecoder().decode(DaemonStatus.self, from: try #require(data))
    }

    @Test func statusReportsHostLinkAndSettings() async throws {
        let status = try decode(await ops.handle(op: "status", body: Data()))
        #expect(status == DaemonStatus(host: "work", buddy: BuddyStatus(link: .notPaired), tokensFromTranscripts: true))
        let unknown = await ops.handle(op: "hook", body: Data())
        #expect(unknown == nil)
    }

    @Test func pairStartsAndCancelStops() async throws {
        let started = try decode(await ops.handle(op: "pair", body: Data()))
        #expect(started.buddy.pairing == .scanning)
        let cancelled = try decode(await ops.handle(op: "pair-cancel", body: Data()))
        #expect(cancelled.buddy.pairing == .idle)
    }

    @Test func hostIsNormalizedSavedAppliedAndRelinksOnce() async throws {
        let status = try decode(await ops.handle(op: "host", body: Data("Home Mac".utf8)))
        #expect(status.host == "home-mac")
        let applied = await coordinator.currentHost
        #expect(applied == "home-mac")
        #expect(HiloConfig.load(path: path).host == "home-mac")
        #expect(buddy.reconnects == 1)
        _ = await ops.handle(op: "host", body: Data("home mac".utf8))
        #expect(buddy.reconnects == 1)
        let rejected = String(decoding: await ops.handle(op: "host", body: Data("???".utf8)) ?? Data(), as: UTF8.self)
        #expect(rejected.hasPrefix("rejected"))
        let kept = await coordinator.currentHost
        #expect(kept == "home-mac")
    }

    @Test func hostChangeKeepsOtherSettings() async throws {
        try HiloConfig(host: "work", tokensFromTranscripts: true).save(path: path)
        _ = await ops.handle(op: "host", body: Data("Studio".utf8))
        #expect(HiloConfig.load(path: path) == HiloConfig(host: "studio", tokensFromTranscripts: true))
    }
}
