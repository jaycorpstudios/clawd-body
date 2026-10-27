enum Schema {
    /// Append only; `PRAGMA user_version` counts the applied entries.
    static let migrations = [
        """
        CREATE TABLE project (
          id INTEGER PRIMARY KEY, name TEXT NOT NULL UNIQUE, color TEXT NOT NULL, jira_key TEXT);
        CREATE TABLE task (
          id INTEGER PRIMARY KEY, project_id INTEGER REFERENCES project(id) ON DELETE SET NULL,
          title TEXT NOT NULL, notes TEXT NOT NULL DEFAULT '',
          status TEXT NOT NULL CHECK (status IN ('todo', 'doing', 'done')), jira_ref TEXT,
          created_at INTEGER NOT NULL, started_at INTEGER, done_at INTEGER);
        CREATE TABLE session (
          id TEXT PRIMARY KEY, project_id INTEGER REFERENCES project(id) ON DELETE SET NULL,
          task_id INTEGER REFERENCES task(id) ON DELETE SET NULL,
          status TEXT NOT NULL, started_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, ended_at INTEGER,
          last_action TEXT NOT NULL, waiting_on TEXT, summary TEXT, tokens INTEGER);
        CREATE TABLE session_step (
          session_id TEXT NOT NULL REFERENCES session(id) ON DELETE CASCADE,
          ts INTEGER NOT NULL, kind TEXT NOT NULL, text TEXT NOT NULL);
        CREATE INDEX session_step_session ON session_step(session_id);
        CREATE TABLE agreement (
          id INTEGER PRIMARY KEY, project_id INTEGER REFERENCES project(id) ON DELETE SET NULL,
          task_id INTEGER REFERENCES task(id) ON DELETE SET NULL,
          text TEXT NOT NULL, context TEXT NOT NULL DEFAULT '',
          origin TEXT NOT NULL CHECK (origin IN ('meeting', 'session', 'manual')),
          status TEXT NOT NULL CHECK (status IN ('confirmed', 'pending')), ts INTEGER NOT NULL);
        CREATE TABLE daemon_state (
          id INTEGER PRIMARY KEY CHECK (id = 1), buddy_connected INTEGER NOT NULL, updated_at INTEGER NOT NULL);
        """,
        """
        ALTER TABLE session ADD COLUMN repo TEXT;
        CREATE TABLE git_commit (
          repo TEXT NOT NULL, hash TEXT NOT NULL, branch TEXT NOT NULL, message TEXT NOT NULL, ts INTEGER NOT NULL,
          project_id INTEGER REFERENCES project(id) ON DELETE SET NULL,
          task_id INTEGER REFERENCES task(id) ON DELETE SET NULL,
          PRIMARY KEY (repo, hash));
        CREATE INDEX git_commit_ts ON git_commit(ts);
        CREATE TABLE activity (
          id INTEGER PRIMARY KEY, project_id INTEGER REFERENCES project(id) ON DELETE CASCADE,
          ts_start INTEGER NOT NULL, ts_end INTEGER NOT NULL);
        CREATE INDEX activity_end ON activity(ts_end);
        """,
        """
        CREATE TABLE focus_cycle (
          id INTEGER PRIMARY KEY, ended_at INTEGER NOT NULL, work_min INTEGER NOT NULL,
          task_id INTEGER REFERENCES task(id) ON DELETE SET NULL);
        CREATE INDEX focus_cycle_end ON focus_cycle(ended_at);
        """,
    ]

    static func migrate(_ db: Database) throws {
        let applied = try db.rows("PRAGMA user_version").first?.int(0) ?? 0
        guard applied < migrations.count else { return }
        try db.transaction {
            for (i, sql) in migrations.enumerated().dropFirst(applied) {
                try db.execute(sql)
                try db.execute("PRAGMA user_version = \(i + 1)")
            }
        }
    }
}
