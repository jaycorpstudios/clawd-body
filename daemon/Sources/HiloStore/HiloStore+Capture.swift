import Foundation

/// Automatic capture: git commits in the repos of Claude Code sessions, and active time per project.
extension HiloStore {
    /// Activity closer together than this joins one span; a longer gap is a pause.
    public static let activityGap = 300

    public func setRepo(session: String, repo: String) throws {
        try db.run("UPDATE session SET repo = ? WHERE id = ? AND repo IS NULL", [repo, session])
    }

    /// Only sessions the hooks already recorded; a transcript of an unknown session is ignored.
    public func setTokens(session: String, tokens: Int) throws {
        try db.run("UPDATE session SET tokens = ? WHERE id = ?", [tokens, session])
    }

    /// Repos of sessions active since `since`, with the session's project.
    public func sessionRepos(since: Int) throws -> [(repo: String, project: String?)] {
        try db.rows("""
            SELECT s.repo, max(p.name) FROM session s LEFT JOIN project p ON p.id = s.project_id
            WHERE s.repo IS NOT NULL AND (s.ended_at IS NULL OR s.updated_at >= ?) GROUP BY s.repo
            """, [since]).map { ($0.text(0) ?? "", $0.text(1)) }
    }

    /// Marks the session's project as active at `now`, extending its last span unless the gap was a pause.
    public func recordActivity(session: String, now: Int) throws {
        guard let projectId = try db.rows("SELECT project_id FROM session WHERE id = ?", [session]).first?.int(0) else { return }
        try recordActivity(projectId: projectId, now: now)
    }

    public func recordActivity(project: String, now: Int) throws {
        try recordActivity(projectId: try self.project(named: project).id, now: now)
    }

    private func recordActivity(projectId: Int, now: Int) throws {
        try db.transaction { try extendActivity(projectId: projectId, now: now) }
    }

    /// Activity older than the project's last span is ignored.
    private func extendActivity(projectId: Int, now: Int) throws {
        let last = try db.rows("SELECT id, ts_end FROM activity WHERE project_id = ? ORDER BY ts_end DESC LIMIT 1", [projectId]).first
        let end = last?.int(1)
        if let last, let end, now >= end, now - end <= Self.activityGap {
            try db.run("UPDATE activity SET ts_end = ? WHERE id = ?", [now, last.int(0)!])
        } else if end.map({ now > $0 }) ?? true {
            try db.run("INSERT INTO activity (project_id, ts_start, ts_end) VALUES (?, ?, ?)", [projectId, now, now])
        }
    }

    /// Active seconds per project name between `since` and `until` (spans are clipped at both).
    public func activeSeconds(since: Int, until: Int = Int.max) throws -> [String: Int] {
        var out: [String: Int] = [:]
        for r in try db.rows("""
            SELECT p.name, sum(min(a.ts_end, ?) - max(a.ts_start, ?)) FROM activity a JOIN project p ON p.id = a.project_id
            WHERE a.ts_end > ? AND a.ts_start < ? GROUP BY p.name
            """, [until, since, since, until]) {
            out[r.text(0) ?? ""] = r.int(1) ?? 0
        }
        return out
    }

    /// Active seconds per day start (local calendar) between `since` and `until`, all projects together.
    public func activeSecondsPerDay(since: Int, until: Int = Int.max, calendar: Calendar = .current) throws -> [Int: Int] {
        var out: [Int: Int] = [:]
        for r in try db.rows("SELECT max(ts_start, ?), min(ts_end, ?) FROM activity WHERE ts_end > ? AND ts_start < ?",
                             [since, until, since, until]) {
            let start = r.int(0) ?? 0, end = r.int(1) ?? 0
            let day = Int(calendar.startOfDay(for: Date(timeIntervalSince1970: TimeInterval(start))).timeIntervalSince1970)
            out[day, default: 0] += end - start
        }
        return out
    }

    /// Inserts commits not seen yet; a new commit links to its project's only task in progress, if there is one.
    @discardableResult
    public func addCommits(_ commits: [CommitRecord], project: String?) throws -> Int {
        guard !commits.isEmpty else { return 0 }
        return try db.transaction {
            let p = try project.map { try self.project(named: $0) }
            let doing = try p.map { try db.rows("SELECT id FROM task WHERE project_id = ? AND status = 'doing'", [$0.id]) } ?? []
            let taskId = doing.count == 1 ? doing[0].int(0) : nil
            var added = 0
            for c in commits {
                guard try db.rows("SELECT 1 FROM git_commit WHERE repo = ? AND hash = ?", [c.repo, c.hash]).first == nil else { continue }
                try db.run("""
                    INSERT INTO git_commit (repo, hash, branch, message, ts, project_id, task_id) VALUES (?, ?, ?, ?, ?, ?, ?)
                    """, [c.repo, c.hash, c.branch, c.message, c.ts, p?.id, taskId])
                if let p { try extendActivity(projectId: p.id, now: c.ts) }
                added += 1
            }
            return added
        }
    }

    public func commits(since: Int) throws -> [CommitRecord] {
        try db.rows(Self.commitSelect + " WHERE c.ts >= ? ORDER BY c.ts DESC", [since]).map(Self.commit)
    }

    public func commits(task id: Int) throws -> [CommitRecord] {
        try db.rows(Self.commitSelect + " WHERE c.task_id = ? ORDER BY c.ts DESC", [id]).map(Self.commit)
    }

    public func commits(project name: String, limit: Int = 10) throws -> [CommitRecord] {
        try db.rows(Self.commitSelect + " WHERE p.name = ? ORDER BY c.ts DESC LIMIT ?", [name, limit]).map(Self.commit)
    }

    private static let commitSelect = """
        SELECT c.repo, c.hash, c.branch, c.message, c.ts, c.task_id, p.id, p.name, p.color, p.jira_key
        FROM git_commit c LEFT JOIN project p ON p.id = c.project_id
        """

    private static func commit(_ r: Row) -> CommitRecord {
        let project = r.int(6).map { Project(id: $0, name: r.text(7) ?? "", color: r.text(8) ?? projectPalette[0], jiraKey: r.text(9)) }
        return CommitRecord(repo: r.text(0) ?? "", hash: r.text(1) ?? "", branch: r.text(2) ?? "", message: r.text(3) ?? "",
                            ts: r.int(4) ?? 0, project: project, taskId: r.int(5))
    }
}
