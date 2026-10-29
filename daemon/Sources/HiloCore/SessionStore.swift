import Foundation
import HiloContract

/// What the buddy should show for this Mac, rebuilt from every message sent to it.
public struct SessionStore: Sendable {
    public static let maxSessions = 8
    public static let maxSteps = 5

    private var sessions: [String: SessionState] = [:]
    private var lastEvent: [String: Int] = [:]
    private var usage = Usage(sessionPct: 0, weeklyPct: 0, resetInMin: 0)
    private var hilo = HiloState(current: nil, next: [], agreementsToday: [])
    private var media: Media?
    private var face: ImageRef?
    private var pomodoro: PomodoroState?
    private var mediaEnabled = true

    public init() {}

    public mutating func apply(_ message: Outbound, now: Int) {
        if let session = message.session { lastEvent[session] = now }
        switch message {
        case .sessionStart(let s):
            sessions[s.session] = SessionState(session: s.session, project: s.project, task: s.task, status: .working, since: now, steps: [],
                                               look: s.look ?? sessions[s.session]?.look)
        case .sessionEnd(let s):
            sessions[s.session] = nil
            lastEvent[s.session] = nil
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
                s.status = r.outcome == .expired ? .waiting : .working
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

    /// The turn ended without a hook (a denial in the terminal).
    public mutating func setIdle(_ session: String, now: Int) {
        update(session, now: now) { $0.status = .idle }
    }

    /// A prompt left in the terminal: waiting, with nothing to answer on the buddy.
    public mutating func setOnMac(_ session: String, project: String, now: Int) {
        ensure(session, project: project, now: now)
        update(session, now: now) { s in
            s.pendingPermission = nil
            s.pendingQuestion = nil
            s.status = .waiting
        }
    }

    /// Working sessions with no event for `seconds` turn idle (an interrupted turn sends no hook); returns them.
    public mutating func idleStale(now: Int, after seconds: Int) -> [String] {
        let stale = sessions.values.filter { $0.status == .working && now - (lastEvent[$0.session] ?? $0.since) >= seconds }.map(\.session)
        for id in stale { update(id, now: now) { $0.status = .idle } }
        return stale
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

    public func project(of session: String) -> String? { sessions[session]?.project }

    public func looks(project: String, except session: String) -> [SessionLook] {
        sessions.values.filter { $0.project == project && $0.session != session }.compactMap(\.look)
    }

    /// nil when this Mac does not know the session; `hue` only fills a session that started without a look.
    public mutating func setLook(session: String, acc: Accessory, hue: Int) -> SessionLook? {
        guard var s = sessions[session] else { return nil }
        let look = SessionLook(hue: s.look?.hue ?? hue, acc: acc)
        s.look = look
        sessions[session] = s
        return look
    }

    public mutating func setMediaEnabled(_ on: Bool) {
        mediaEnabled = on
        if !on { media = nil }
    }

    public func snapshot(maxBytes: Int = Framing.maxMessageSize, host: String = "work") -> Snapshot {
        var ordered = sessions.values.sorted { a, b in
            a.status.priority != b.status.priority ? a.status.priority < b.status.priority : a.since > b.since
        }
        ordered = Array(ordered.prefix(Self.maxSessions))
        var snap = Snapshot(sessions: ordered, usage: usage, hilo: hilo, media: media, face: face, pomodoro: pomodoro,
                            mediaEnabled: mediaEnabled ? nil : false)
        let fits = { (s: Snapshot) in ((try? Wire.encode(.snapshot(s), host: host).count) ?? .max) <= maxBytes }

        if !fits(snap) { snap.sessions = snap.sessions.map { var s = $0; s.steps = nil; return s } }
        if !fits(snap) { snap.sessions = snap.sessions.map { var s = $0; s.pendingPermission?.diff = nil; return s } }
        if !fits(snap) {
            snap.sessions = snap.sessions.map { var s = $0; s.pendingPermission?.why = nil; s.pendingQuestion?.optionDescriptions = nil; s.summary = nil; s.error = nil; return s }
        }
        if !fits(snap) { snap.sessions = snap.sessions.map { var s = $0; s.pendingPermission = s.pendingPermission?.withoutDetailFull(); return s } }
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

extension Outbound {
    public var session: String? {
        switch self {
        case .sessionStart(let s): s.session
        case .sessionEnd(let s): s.session
        case .agentStep(let s): s.session
        case .needsPermission(let p): p.session
        case .question(let q): q.session
        case .requestResolved(let r): r.session
        case .taskDone(let d): d.session
        case .agentError(let e): e.session
        case .snapshot, .usageUpdate, .usageWindowReset, .hiloTaskChanged, .nowPlaying, .settingsSet, .face, .cover, .pomodoro: nil
        }
    }
}

extension PermissionRequest {
    /// The longest host name, so the message fits whichever Mac sends it.
    static let widestHost = String(repeating: "x", count: 16)

    /// Drops what the 8 KB message cap cannot carry: the diff first, then `detail_full`.
    public func fitted(maxBytes: Int = Framing.maxMessageSize) -> PermissionRequest {
        let fits = { (p: PermissionRequest) in ((try? Wire.encode(.needsPermission(p), host: Self.widestHost).count) ?? .max) <= maxBytes }
        var p = self
        if !fits(p) { p.diff = nil }
        if !fits(p) { p = p.withoutDetailFull() }
        return p
    }

    /// Without the whole text the buddy shows only the cut `detail`, so it may no longer approve.
    func withoutDetailFull() -> PermissionRequest {
        guard detailFull != nil else { return self }
        var p = self
        p.detailFull = nil
        p.remoteAllowed = false
        return p
    }
}
