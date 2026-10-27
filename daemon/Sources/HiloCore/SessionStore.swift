import Foundation
import HiloContract

/// What the buddy should show for this Mac, rebuilt from every message sent to it.
public struct SessionStore: Sendable {
    public static let maxSessions = 8
    public static let maxSteps = 5

    private var sessions: [String: SessionState] = [:]
    private var usage = Usage(sessionPct: 0, weeklyPct: 0, resetInMin: 0)
    private var hilo = HiloState(current: nil, next: [], agreementsToday: [])
    private var media: Media?
    private var face: ImageRef?
    private var pomodoro: PomodoroState?

    public init() {}

    public mutating func apply(_ message: Outbound, now: Int) {
        switch message {
        case .sessionStart(let s):
            sessions[s.session] = SessionState(session: s.session, project: s.project, task: s.task, status: .working, since: now, steps: [])
        case .sessionEnd(let s):
            sessions[s.session] = nil
        case .agentStep(let step):
            update(step.session, now: now) { s in
                if s.pendingPermission == nil && s.pendingQuestion == nil { s.status = .working }
                s.steps = Array(((s.steps ?? []) + [Step(ts: now, kind: step.kind, text: step.text)]).suffix(Self.maxSteps))
            }
        case .needsPermission(let p):
            ensure(p.session, project: p.project, now: now)
            update(p.session, now: now) { $0.status = .waiting; $0.pendingPermission = p; $0.pendingQuestion = nil }
        case .question(let q):
            ensure(q.session, project: q.project, now: now)
            update(q.session, now: now) { $0.status = .waiting; $0.pendingQuestion = q; $0.pendingPermission = nil }
        case .requestResolved(let r):
            update(r.session, now: now) { s in
                guard s.pendingPermission?.requestId == r.requestId || s.pendingQuestion?.requestId == r.requestId else { return }
                s.pendingPermission = nil
                s.pendingQuestion = nil
                s.status = .working
            }
        case .taskDone(let d):
            update(d.session, now: now) { $0.status = .done; $0.summary = d.summary; $0.error = nil }
        case .agentError(let e):
            update(e.session, now: now) { $0.status = .error; $0.error = e.detail }
        case .usageUpdate(let u):
            usage = u
        case .usageWindowReset:
            usage.sessionPct = 0
        case .hiloTaskChanged(let t):
            hilo.current = t
        case .nowPlaying(let m):
            media = m
        case .snapshot, .settingsSet, .face, .cover, .pomodoro:
            break
        }
    }

    public mutating func setHilo(_ state: HiloState) {
        hilo = state
    }

    public mutating func setUsage(_ value: Usage) {
        usage = value
    }

    public mutating func setFace(_ value: ImageRef?) {
        face = value
    }

    public mutating func setPomodoro(_ value: PomodoroState?) {
        pomodoro = value
    }

    public mutating func setMedia(_ value: Media?) {
        media = value
    }

    public func snapshot(maxBytes: Int = Framing.maxMessageSize, host: String = "work") -> Snapshot {
        var ordered = sessions.values.sorted { a, b in
            a.status.priority != b.status.priority ? a.status.priority < b.status.priority : a.since > b.since
        }
        ordered = Array(ordered.prefix(Self.maxSessions))
        var snap = Snapshot(sessions: ordered, usage: usage, hilo: hilo, media: media, face: face, pomodoro: pomodoro)
        let fits = { (s: Snapshot) in ((try? Wire.encode(.snapshot(s), host: host).count) ?? .max) <= maxBytes }

        if !fits(snap) { snap.sessions = snap.sessions.map { var s = $0; s.steps = nil; return s } }
        if !fits(snap) { snap.sessions = snap.sessions.map { var s = $0; s.pendingPermission?.diff = nil; return s } }
        if !fits(snap) {
            snap.sessions = snap.sessions.map { var s = $0; s.pendingPermission?.why = nil; s.summary = nil; s.error = nil; return s }
        }
        while !fits(snap), !snap.sessions.isEmpty { snap.sessions.removeLast() }
        return snap
    }

    private mutating func ensure(_ session: String, project: String, now: Int) {
        if sessions[session] == nil {
            sessions[session] = SessionState(session: session, project: project, task: "", status: .working, since: now, steps: [])
        }
    }

    private mutating func update(_ session: String, now: Int, _ change: (inout SessionState) -> Void) {
        guard var s = sessions[session] else { return }
        let before = s.status
        change(&s)
        if s.status != before { s.since = now }
        sessions[session] = s
    }
}

extension SessionStatus {
    var priority: Int {
        switch self {
        case .waiting: 0
        case .error: 1
        case .working: 2
        case .done: 3
        case .idle: 4
        }
    }
}
