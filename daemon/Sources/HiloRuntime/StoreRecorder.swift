import Foundation
import HiloContract
import HiloCore
import HiloStore

/// Mirrors every message sent to the buddy into Hilo's SQLite store, and reads back what the buddy shows of Hilo.
public struct StoreRecorder: Sendable {
    private let store: HiloStore
    private let log: @Sendable (String) -> Void

    public init(store: HiloStore, log: @escaping @Sendable (String) -> Void = { _ in }) {
        self.store = store; self.log = log
    }

    public func record(_ message: Outbound, now: Int) {
        do {
            switch message {
            case .sessionStart(let s):
                try store.recordSessionStart(s.session, project: s.project, look: s.look, now: now)
            case .sessionEnd(let s):
                try store.endSession(s.session, now: now)
            case .agentStep(let s):
                try store.recordStep(s.session, project: nil, kind: s.kind, text: s.text, status: nil, now: now)
                try store.markWorking(s.session)
            case .needsPermission(let p):
                let text = "\(p.tool): \(p.detail)"
                try store.recordStep(p.session, project: p.project, kind: .ask, text: text, status: .waiting, waitingOn: text, now: now)
            case .question(let q):
                try store.recordStep(q.session, project: q.project, kind: .ask, text: q.detail, status: .waiting, waitingOn: q.detail, now: now)
            case .requestResolved(let r):
                try store.recordStep(r.session, project: nil, kind: r.outcome == .approved || r.outcome == .answered ? .ok : .deny,
                                     text: Self.describe(r), status: .working, now: now)
            case .taskDone(let d):
                try store.recordStep(d.session, project: nil, kind: .ok, text: d.summary, status: .done, now: now)
                try store.finishSession(d.session, status: .done, summary: d.summary, now: now)
            case .agentError(let e):
                try store.recordStep(e.session, project: nil, kind: .err, text: e.detail, status: .error, now: now)
            case .snapshot, .usageUpdate, .usageWindowReset, .hiloTaskChanged, .nowPlaying, .settingsSet, .face, .cover, .pomodoro:
                break
            }
            if let session = Self.session(of: message) { try store.recordActivity(session: session, now: now) }
        } catch {
            log("store: \(error)")
        }
    }

    public func attach(session: String, project: String, repo: String?) {
        do {
            try store.setProjectIfMissing(session: session, project: project)
            if let repo { try store.setRepo(session: session, repo: repo) }
        } catch { log("store: \(error)") }
    }

    private static func session(of message: Outbound) -> String? {
        switch message {
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

    public func look(session: String) -> SessionLook? {
        (try? store.look(session: session)) ?? nil
    }

    public func saveLook(session: String, look: SessionLook) {
        do { try store.setLook(session: session, look: look) } catch { log("store: \(error)") }
    }

    public func saveFocus(_ state: PomodoroState, finishedCycles: Int, now: Int) {
        do { try store.saveFocus(state, finishedCycles: finishedCycles, now: now) } catch { log("store: \(error)") }
    }

    public func savedFocus() -> PomodoroState? {
        do { return try store.focusState() } catch { log("store: \(error)"); return nil }
    }

    public func buddyLink(up: Bool, now: Int) {
        do { try store.setBuddyConnected(up, now: now) } catch { log("store: \(error)") }
    }

    public func hiloState(now: Int) -> HiloState {
        let dayStart = Int(Calendar.current.startOfDay(for: Date(timeIntervalSince1970: TimeInterval(now))).timeIntervalSince1970)
        do {
            let tasks = try store.tasks(doneSince: dayStart)
            let current = try store.currentTask().map {
                HiloTask(title: Text.clip($0.title, 120), project: Self.project($0), jira: Self.jira($0), startedAt: $0.startedAt ?? $0.createdAt)
            }
            let next = tasks.filter { $0.status == .todo }.prefix(3)
                .map { HiloNext(title: Text.clip($0.title, 120), project: Self.project($0), jira: Self.jira($0)) }
            let agreements = try store.agreements().filter { $0.status == .confirmed && $0.ts >= dayStart }.prefix(3)
                .map { Text.clip($0.text, 120) }
            return HiloState(current: current, next: Array(next), agreementsToday: Array(agreements))
        } catch {
            log("store: \(error)")
            return HiloState(current: nil, next: [], agreementsToday: [])
        }
    }

    private static func project(_ t: HiloTaskRecord) -> String {
        Text.clip(t.project?.name ?? "inbox", 64)
    }

    private static func jira(_ t: HiloTaskRecord) -> String? {
        t.jiraRef.flatMap { $0.wholeMatch(of: /[A-Z][A-Z0-9]{1,9}-[0-9]{1,7}/) != nil ? $0 : nil }
    }

    private static func describe(_ r: RequestResolved) -> String {
        let place = switch r.via { case .buddy: "on the buddy"; case .mac: "on the Mac"; case .timeout: "to the Mac" }
        return switch r.outcome {
        case .approved: "Approved \(place)"
        case .denied: "Denied \(place)"
        case .answered: "Answered \(place)"
        case .expired: "Handed back \(place)"
        }
    }
}
