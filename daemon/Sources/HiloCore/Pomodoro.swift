import HiloContract

/// The same rules as the buddy's `bm_desk.c`, so both sides flip phases on their own without messages.
extension PomodoroState {
    public static let defaultWorkMin = 25, defaultBreakMin = 5

    public static func stopped(workMin: Int = defaultWorkMin, breakMin: Int = defaultBreakMin, now: Int) -> PomodoroState {
        PomodoroState(state: .stopped, phase: .work, workMin: workMin, breakMin: breakMin, cycle: 0, updatedAt: now)
    }

    var phaseSeconds: Int { (phase == .work ? workMin : breakMin) * 60 }

    public func left(now: Int) -> Int {
        switch state {
        case .stopped: phaseSeconds
        case .paused: leftS ?? 0
        case .running: max(0, (endsAt ?? now) - now)
        }
    }

    /// Flips every phase that ended by `now`; each finished work phase adds a cycle.
    public mutating func advance(to now: Int) {
        var flips = 0
        while state == .running, let end = endsAt, now >= end, flips < 1000 {
            if phase == .work, cycle < 999 { cycle += 1 }
            phase = phase == .work ? .rest : .work
            endsAt = end + phaseSeconds
            flips += 1
        }
    }

    public mutating func toggle(now: Int) {
        if state == .running {
            leftS = min(5400, left(now: now))
            endsAt = nil
            state = .paused
        } else {
            endsAt = now + (state == .paused ? leftS ?? phaseSeconds : phaseSeconds)
            leftS = nil
            state = .running
        }
        updatedAt = now
    }

    public mutating func reset(now: Int) {
        self = .stopped(workMin: workMin, breakMin: breakMin, now: now)
    }

    /// Durations change only while stopped, like on the buddy.
    public mutating func setDurations(work: Int?, rest: Int?, now: Int) -> Bool {
        guard state == .stopped else { return false }
        let w = work ?? workMin, b = rest ?? breakMin
        guard (1...90).contains(w), (1...60).contains(b) else { return false }
        workMin = w; breakMin = b; updatedAt = now
        return true
    }
}

public enum PomodoroCommand: Equatable, Sendable {
    case toggle, reset, durations(work: Int?, rest: Int?)
}

/// Announces each phase end once, from the states `hilod` reports; a change made by hand (new `updatedAt`) is never announced.
public struct PhaseAlarm: Sendable {
    public static let staleAfter = 30
    private var watched: PomodoroState?

    public init() {}

    /// The phase that just began, when one began since the last call and less than `staleAfter` seconds ago.
    public mutating func check(_ state: PomodoroState?, now: Int) -> PomodoroState? {
        guard let state, state.state == .running else {
            watched = nil
            return nil
        }
        guard var seen = watched, seen.updatedAt == state.updatedAt, let end = seen.endsAt else {
            var fresh = state
            fresh.advance(to: now)
            watched = fresh
            return nil
        }
        seen.advance(to: now)
        watched = seen
        guard let next = seen.endsAt, next != end else { return nil }
        return now - (next - seen.phaseSeconds) < Self.staleAfter ? seen : nil
    }
}
