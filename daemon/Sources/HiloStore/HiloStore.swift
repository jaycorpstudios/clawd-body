import Foundation
import HiloContract

/// Hilo's data on this Mac. `hilod` records sessions; the app and the CLI own tasks and agreements.
public final class HiloStore: @unchecked Sendable {
    public static let projectPalette = ["#0e7c72", "#5b8cff", "#b98ae0", "#ff9a52", "#e0607e", "#4fd39a", "#ffc53d", "#7cc8ff"]

    let db: Database

    /// `HILO_DB` overrides the location (tests, a scratch database).
    public static var defaultPath: String {
        if let path = ProcessInfo.processInfo.environment["HILO_DB"] { return path }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appending(path: "Hilo/hilo.sqlite").path(percentEncoded: false)
    }

    public init(path: String = HiloStore.defaultPath) throws {
        try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent,
                                                withIntermediateDirectories: true)
        db = try Database(path: path)
        try Schema.migrate(db)
    }

    public func projects() throws -> [Project] {
        try db.rows("SELECT id, name, color, jira_key FROM project ORDER BY name").map(Self.project)
    }

    @discardableResult
    public func project(named name: String) throws -> Project {
        if let row = try db.rows("SELECT id, name, color, jira_key FROM project WHERE name = ?", [name]).first {
            return Self.project(row)
        }
        let count = try db.rows("SELECT count(*) FROM project").first?.int(0) ?? 0
        let color = Self.projectPalette[count % Self.projectPalette.count]
        let id = try db.run("INSERT INTO project (name, color) VALUES (?, ?)", [name, color])
        return Project(id: id, name: name, color: color, jiraKey: nil)
    }

    @discardableResult
    public func addTask(_ title: String, project: String?, status: TaskStatus = .todo, now: Int) throws -> HiloTaskRecord {
        let projectId = try project.map { try self.project(named: $0).id }
        let id = try db.run("INSERT INTO task (project_id, title, status, created_at, started_at) VALUES (?, ?, ?, ?, ?)",
                            [projectId, title, status.rawValue, now, status == .doing ? now : nil])
        return try task(id)!
    }

    public func task(_ id: Int) throws -> HiloTaskRecord? {
        try db.rows(Self.taskSelect + " WHERE t.id = ?", [id]).first.map(Self.task)
    }

    /// Open tasks plus those finished since `doneSince`.
    public func tasks(doneSince: Int) throws -> [HiloTaskRecord] {
        try db.rows(Self.taskSelect + " WHERE t.status != 'done' OR t.done_at >= ? ORDER BY t.created_at", [doneSince])
            .map(Self.task)
    }

    public func setStatus(task id: Int, _ status: TaskStatus, now: Int) throws {
        switch status {
        case .todo: try db.run("UPDATE task SET status = 'todo', done_at = NULL WHERE id = ?", [id])
        case .doing: try db.run("UPDATE task SET status = 'doing', done_at = NULL, started_at = coalesce(started_at, ?) WHERE id = ?", [now, id])
        case .done: try db.run("UPDATE task SET status = 'done', done_at = ? WHERE id = ?", [now, id])
        }
    }

    public func update(task id: Int, title: String, notes: String) throws {
        try db.run("UPDATE task SET title = ?, notes = ? WHERE id = ?", [title, notes, id])
    }

    public func deleteTask(_ id: Int) throws {
        try db.run("DELETE FROM task WHERE id = ?", [id])
    }

    /// The task shown on the buddy: the most recently started one in progress.
    public func currentTask() throws -> HiloTaskRecord? {
        try db.rows(Self.taskSelect + " WHERE t.status = 'doing' ORDER BY t.started_at DESC LIMIT 1").first.map(Self.task)
    }

    /// A session that already has a look keeps it.
    public func recordSessionStart(_ session: String, project: String, look: SessionLook? = nil, now: Int) throws {
        let p = try self.project(named: project)
        let doing = try db.rows("SELECT id FROM task WHERE project_id = ? AND status = 'doing'", [p.id])
        let taskId = doing.count == 1 ? doing[0].int(0) : nil
        try db.run("""
            INSERT INTO session (id, project_id, task_id, status, started_at, updated_at, last_action, look_hue, look_acc)
            VALUES (?, ?, ?, 'working', ?, ?, 'Session started', ?, ?)
            ON CONFLICT(id) DO UPDATE SET project_id = excluded.project_id, status = 'working', ended_at = NULL,
              updated_at = excluded.updated_at, task_id = coalesce(session.task_id, excluded.task_id),
              look_hue = coalesce(session.look_hue, excluded.look_hue), look_acc = coalesce(session.look_acc, excluded.look_acc)
            """, [session, p.id, taskId, now, now, look?.hue, look?.acc.rawValue])
    }

    /// Adds a step, creating the session if it began before `hilod` started.
    public func recordStep(_ session: String, project: String?, kind: StepKind, text: String,
                           status: SessionStatus?, waitingOn: String? = nil, now: Int) throws {
        try db.transaction {
            let projectId = try project.map { try self.project(named: $0).id }
            try db.run("""
                INSERT INTO session (id, project_id, status, started_at, updated_at, last_action)
                VALUES (?, ?, 'working', ?, ?, '') ON CONFLICT(id) DO UPDATE SET
                  project_id = coalesce(session.project_id, excluded.project_id)
                """, [session, projectId, now, now])
            try db.run("INSERT INTO session_step (session_id, ts, kind, text) VALUES (?, ?, ?, ?)",
                       [session, now, kind.rawValue, text])
            try db.run("""
                UPDATE session SET last_action = ?, updated_at = ?, status = coalesce(?, status),
                  waiting_on = CASE WHEN ? IS NULL THEN waiting_on ELSE ? END WHERE id = ?
                """, [text, now, status?.rawValue, status?.rawValue, waitingOn, session])
        }
    }

    /// Fills in the project of a session first seen through a message that carries none.
    public func setProjectIfMissing(session: String, project: String) throws {
        guard try db.rows("SELECT 1 FROM session WHERE id = ? AND project_id IS NULL", [session]).first != nil else { return }
        try db.run("UPDATE session SET project_id = ? WHERE id = ?", [try self.project(named: project).id, session])
    }

    public func finishSession(_ session: String, status: SessionStatus, summary: String?, now: Int) throws {
        try db.run("UPDATE session SET status = ?, summary = coalesce(?, summary), waiting_on = NULL, updated_at = ? WHERE id = ?",
                   [status.rawValue, summary, now, session])
    }

    public func endSession(_ session: String, now: Int) throws {
        try db.run("""
            UPDATE session SET ended_at = ?, updated_at = ?, waiting_on = NULL,
              status = CASE status WHEN 'error' THEN 'error' ELSE 'done' END WHERE id = ?
            """, [now, now, session])
    }

    public func sessions(since: Int) throws -> [SessionRecord] {
        try db.rows(Self.sessionSelect + " WHERE s.ended_at IS NULL OR s.updated_at >= ? ORDER BY s.updated_at DESC", [since])
            .map(Self.session)
    }

    public func sessions(task id: Int) throws -> [SessionRecord] {
        try db.rows(Self.sessionSelect + " WHERE s.task_id = ? ORDER BY s.updated_at DESC", [id]).map(Self.session)
    }

    public func steps(session: String, limit: Int = 50) throws -> [StepRecord] {
        try db.rows("SELECT ts, kind, text FROM session_step WHERE session_id = ? ORDER BY rowid DESC LIMIT ?", [session, limit])
            .reversed()
            .map { StepRecord(ts: $0.int(0) ?? 0, kind: StepKind(rawValue: $0.text(1) ?? "") ?? .plan, text: $0.text(2) ?? "") }
    }

    public func link(session: String, task: Int?) throws {
        try db.run("UPDATE session SET task_id = ? WHERE id = ?", [task, session])
    }

    @discardableResult
    public func addAgreement(_ text: String, project: String?, task: Int? = nil, context: String = "",
                             origin: AgreementOrigin = .manual, status: AgreementStatus = .confirmed, now: Int) throws -> Int {
        let projectId = try project.map { try self.project(named: $0).id }
        return try db.run("INSERT INTO agreement (project_id, task_id, text, context, origin, status, ts) VALUES (?, ?, ?, ?, ?, ?, ?)",
                          [projectId, task, text, context, origin.rawValue, status.rawValue, now])
    }

    public func agreements() throws -> [Agreement] {
        try db.rows("""
            SELECT a.id, a.task_id, a.text, a.context, a.origin, a.status, a.ts, p.id, p.name, p.color, p.jira_key
            FROM agreement a LEFT JOIN project p ON p.id = a.project_id ORDER BY a.ts DESC
            """).map { r in
            Agreement(id: r.int(0)!, project: Self.joinedProject(r, at: 7), taskId: r.int(1), text: r.text(2) ?? "",
                      context: r.text(3) ?? "", origin: AgreementOrigin(rawValue: r.text(4) ?? "") ?? .manual,
                      status: AgreementStatus(rawValue: r.text(5) ?? "") ?? .pending, ts: r.int(6) ?? 0)
        }
    }

    public func confirmAgreement(_ id: Int) throws {
        try db.run("UPDATE agreement SET status = 'confirmed' WHERE id = ?", [id])
    }

    public func deleteAgreement(_ id: Int) throws {
        try db.run("DELETE FROM agreement WHERE id = ?", [id])
    }

    public func setBuddyConnected(_ connected: Bool, now: Int) throws {
        try db.run("""
            INSERT INTO daemon_state (id, buddy_connected, updated_at) VALUES (1, ?, ?)
            ON CONFLICT(id) DO UPDATE SET buddy_connected = excluded.buddy_connected, updated_at = excluded.updated_at
            """, [connected ? 1 : 0, now])
    }

    public func daemonState() throws -> DaemonState? {
        try db.rows("SELECT buddy_connected, updated_at FROM daemon_state WHERE id = 1").first
            .map { DaemonState(buddyConnected: $0.int(0) == 1, updatedAt: $0.int(1) ?? 0) }
    }

    private static let taskSelect = """
        SELECT t.id, t.title, t.notes, t.status, t.jira_ref, t.created_at, t.started_at, t.done_at, p.id, p.name, p.color, p.jira_key
        FROM task t LEFT JOIN project p ON p.id = t.project_id
        """

    private static let sessionSelect = """
        SELECT s.id, s.task_id, t.title, s.status, s.started_at, s.updated_at, s.ended_at, s.last_action, s.waiting_on, s.summary,
          p.id, p.name, p.color, p.jira_key, s.tokens, s.look_hue, s.look_acc
        FROM session s LEFT JOIN project p ON p.id = s.project_id LEFT JOIN task t ON t.id = s.task_id
        """

    private static func project(_ r: Row) -> Project {
        Project(id: r.int(0)!, name: r.text(1) ?? "", color: r.text(2) ?? projectPalette[0], jiraKey: r.text(3))
    }

    private static func joinedProject(_ r: Row, at i: Int) -> Project? {
        r.int(i).map { Project(id: $0, name: r.text(i + 1) ?? "", color: r.text(i + 2) ?? projectPalette[0], jiraKey: r.text(i + 3)) }
    }

    private static func task(_ r: Row) -> HiloTaskRecord {
        HiloTaskRecord(id: r.int(0)!, project: joinedProject(r, at: 8), title: r.text(1) ?? "", notes: r.text(2) ?? "",
                       status: TaskStatus(rawValue: r.text(3) ?? "") ?? .todo, jiraRef: r.text(4), createdAt: r.int(5) ?? 0,
                       startedAt: r.int(6), doneAt: r.int(7))
    }

    private static func session(_ r: Row) -> SessionRecord {
        SessionRecord(id: r.text(0) ?? "", project: joinedProject(r, at: 10), taskId: r.int(1), taskTitle: r.text(2),
                      status: SessionStatus(rawValue: r.text(3) ?? "") ?? .idle, startedAt: r.int(4) ?? 0,
                      updatedAt: r.int(5) ?? 0, endedAt: r.int(6), lastAction: r.text(7) ?? "",
                      waitingOn: r.text(8), summary: r.text(9), tokens: r.int(14),
                      look: r.int(15).flatMap { hue in r.text(16).flatMap(Accessory.init).map { SessionLook(hue: hue, acc: $0) } })
    }
}
