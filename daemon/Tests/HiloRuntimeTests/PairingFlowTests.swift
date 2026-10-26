import Testing
@testable import HiloRuntime

@Suite struct PairingFlowTests {
    @Test func scanConnectAndSecure() {
        var flow = PairingFlow()
        do { let r = flow.start(now: 0); #expect(r) }
        do { let r = flow.start(now: 1); #expect(!r) }
        flow.found(name: "Hilo Buddy", now: 10)
        #expect(flow.state == .connecting && flow.buddyName == "Hilo Buddy")
        do { let r = flow.expire(now: 65); #expect(!r) }
        flow.secured()
        #expect(flow.state == .paired && !flow.active)
        do { let r = flow.start(now: 100); #expect(r) }
    }

    @Test func eachPhaseTimesOut() {
        var flow = PairingFlow()
        _ = flow.start(now: 0)
        do { let r = flow.expire(now: 59); #expect(!r) }
        do { let r = flow.expire(now: 60); #expect(r) }
        #expect(flow.state == .timedOut)
        _ = flow.start(now: 100)
        flow.found(name: "b", now: 150)
        do { let r = flow.expire(now: 200); #expect(!r) }
        do { let r = flow.expire(now: 210); #expect(r) }
    }

    @Test func aDroppedLinkFailsAndCancelReturnsToIdle() {
        var flow = PairingFlow()
        _ = flow.start(now: 0)
        flow.linkLost()
        #expect(flow.state == .scanning)
        flow.found(name: "b", now: 1)
        flow.linkLost()
        #expect(flow.state == .failed)
        _ = flow.start(now: 2)
        flow.cancel()
        #expect(flow.state == .idle)
        flow.secured()
        #expect(flow.state == .idle)
    }
}
