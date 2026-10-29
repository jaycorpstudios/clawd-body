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
        p.setAutoContinue(true, now: 0)
        p.toggle(now: 0)
        p.advance(to: 25 * 60)
        #expect(p.phase == .rest && p.cycle == 1 && p.endsAt == 30 * 60)
        p.advance(to: 3 * 30 * 60 + 10)
        #expect(p.phase == .work && p.cycle == 3 && p.endsAt == 3 * 30 * 60 + 25 * 60)
    }

    @Test func withoutAutoContinueTheNextPhaseWaitsPausedAtItsFullLength() {
        var p = PomodoroState.stopped(now: 0)
        p.toggle(now: 0)
        #expect(p.advance(to: 25 * 60 - 1) == nil)
        #expect(p.advance(to: 3 * 30 * 60) == 25 * 60)
        #expect(p.state == .paused && p.phase == .rest && p.cycle == 1 && p.leftS == 5 * 60 && p.endsAt == nil && p.isValid)
        #expect(p.advance(to: 10 * 30 * 60) == nil && p.left(now: 10 * 30 * 60) == 5 * 60)
        p.reset(now: 0)
        p.setAutoContinue(true, now: 1)
        p.reset(now: 2)
        #expect(p.autoContinue == true && p.updatedAt == 2)
    }

    @Test func startsTheChosenPhaseFromStoppedOrAWaitingPhase() {
        var p = PomodoroState.stopped(now: 0)
        #expect(p.ready)
        p.start(.rest, now: 100)
        #expect(p.state == .running && p.phase == .rest && p.endsAt == 100 + 5 * 60 && p.cycle == 0 && p.updatedAt == 100 && p.isValid)
        p.advance(to: 100 + 5 * 60)
        #expect(p.state == .paused && p.phase == .work && p.ready && p.cycle == 0)
        p.start(.rest, now: 1000)
        #expect(p.phase == .rest && p.endsAt == 1000 + 5 * 60 && p.leftS == nil && p.isValid)
        p.toggle(now: 1010)
        #expect(!p.ready)
    }

    @Test func phaseAlarmAnnouncesAPhaseThatWaitsPaused() {
        var alarm = PhaseAlarm()
        var p = PomodoroState.stopped(now: 0)
        p.toggle(now: 10)
        #expect(alarm.check(p, now: 12) == nil)
        let rest = alarm.check(p, now: 10 + 25 * 60 + 1)
        #expect(rest?.phase == .rest && rest?.state == .paused)
        #expect(alarm.check(p, now: 10 + 25 * 60 + 3) == nil)
        var paused = p
        paused.advance(to: 10 + 25 * 60 + 4)
        #expect(alarm.check(paused, now: 10 + 25 * 60 + 5) == nil)
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

    @Test func phaseAlarmAnnouncesEachEndOnceAndNeverAHandChange() {
        var alarm = PhaseAlarm()
        var p = PomodoroState.stopped(now: 0)
        p.setAutoContinue(true, now: 0)
        #expect(alarm.check(p, now: 0) == nil)
        p.toggle(now: 10)
        #expect(alarm.check(p, now: 12) == nil)
        #expect(alarm.check(p, now: 10 + 25 * 60 - 1) == nil)
        let rest = alarm.check(p, now: 10 + 25 * 60 + 1)
        #expect(rest?.phase == .rest && rest?.cycle == 1)
        #expect(alarm.check(p, now: 10 + 25 * 60 + 3) == nil)
        var advanced = p
        advanced.advance(to: 10 + 25 * 60 + 4)
        #expect(alarm.check(advanced, now: 10 + 25 * 60 + 5) == nil)
        #expect(alarm.check(p, now: 10 + 30 * 60 + 2)?.phase == .work)

        p.toggle(now: 10 + 30 * 60 + 10)
        p.toggle(now: 10 + 30 * 60 + 20)
        #expect(alarm.check(p, now: 10 + 30 * 60 + 21) == nil)
    }

    @Test func phaseAlarmStaysQuietForAPhaseThatEndedLongAgo() {
        var alarm = PhaseAlarm()
        var p = PomodoroState.stopped(now: 0)
        p.toggle(now: 0)
        #expect(alarm.check(p, now: 1) == nil)
        #expect(alarm.check(p, now: 25 * 60 + PhaseAlarm.staleAfter) == nil)
        #expect(alarm.check(p, now: 25 * 60 + PhaseAlarm.staleAfter + 10) == nil)
        p.reset(now: 2000)
        #expect(alarm.check(p, now: 2001) == nil)
    }
}
