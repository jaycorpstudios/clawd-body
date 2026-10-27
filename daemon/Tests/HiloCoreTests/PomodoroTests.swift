import Testing
import HiloContract
@testable import HiloCore

@Suite struct PomodoroTests {
    @Test func runsPausesAndResumesWithTheLeftTime() {
        var p = PomodoroState.stopped(now: 0)
        #expect(p.left(now: 0) == 25 * 60)
        p.toggle(now: 100)
        #expect(p.state == .running && p.endsAt == 100 + 25 * 60 && p.isValid)
        p.toggle(now: 160)
        #expect(p.state == .paused && p.leftS == 25 * 60 - 60 && p.endsAt == nil && p.isValid)
        p.toggle(now: 1000)
        #expect(p.endsAt == 1000 + 25 * 60 - 60 && p.updatedAt == 1000)
    }

    @Test func phasesFlipLikeTheBuddyAndCountFinishedWork() {
        var p = PomodoroState.stopped(now: 0)
        p.toggle(now: 0)
        p.advance(to: 25 * 60)
        #expect(p.phase == .rest && p.cycle == 1 && p.endsAt == 30 * 60)
        p.advance(to: 3 * 30 * 60 + 10)
        #expect(p.phase == .work && p.cycle == 3 && p.endsAt == 3 * 30 * 60 + 25 * 60)
    }

    @Test func durationsOnlyWhileStoppedAndInRange() {
        var p = PomodoroState.stopped(now: 0)
        let set = p.setDurations(work: 50, rest: nil, now: 5)
        #expect(set && p.workMin == 50 && p.breakMin == 5)
        let tooLong = p.setDurations(work: 91, rest: nil, now: 6)
        p.toggle(now: 10)
        let running = p.setDurations(work: 30, rest: 10, now: 11)
        #expect(!tooLong && !running)
        p.reset(now: 20)
        #expect(p.state == .stopped && p.workMin == 50 && p.cycle == 0 && p.isValid)
    }
}
