import Foundation

/// Finished Pomodoro work phases, each linked to the task in progress when it ended.
extension HiloStore {
    public func recordFocusCycles(_ count: Int, workMin: Int, now: Int) throws {
        guard count > 0 else { return }
        let task = try currentTask()?.id
        try db.transaction {
            for _ in 0..<count {
                try db.run("INSERT INTO focus_cycle (ended_at, work_min, task_id) VALUES (?, ?, ?)", [now, workMin, task])
            }
        }
    }

    public func focusCycles(since: Int) throws -> (count: Int, minutes: Int) {
        let row = try db.rows("SELECT count(*), coalesce(sum(work_min), 0) FROM focus_cycle WHERE ended_at >= ?", [since]).first
        return (row?.int(0) ?? 0, row?.int(1) ?? 0)
    }

    public func focusCycles(task id: Int) throws -> Int {
        try db.rows("SELECT count(*) FROM focus_cycle WHERE task_id = ?", [id]).first?.int(0) ?? 0
    }
}
