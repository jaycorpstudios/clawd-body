import Foundation
import HiloContract

/// Finished Pomodoro work phases, each linked to the task in progress when it ended.
extension HiloStore {
    /// Saved with the cycles it finished in one transaction, so a restarted `hilod` neither loses nor repeats them.
    public func saveFocus(_ state: PomodoroState, finishedCycles: Int, now: Int) throws {
        let task = finishedCycles > 0 ? try currentTask()?.id : nil
        let json = String(decoding: try JSONEncoder().encode(state), as: UTF8.self)
        try db.transaction {
            for _ in 0..<max(0, finishedCycles) {
                try db.run("INSERT INTO focus_cycle (ended_at, work_min, task_id) VALUES (?, ?, ?)", [now, state.workMin, task])
            }
            try db.run("INSERT INTO focus_state (id, json) VALUES (1, ?) ON CONFLICT(id) DO UPDATE SET json = excluded.json", [json])
        }
    }

    public func focusState() throws -> PomodoroState? {
        guard let json = try db.rows("SELECT json FROM focus_state WHERE id = 1").first?.text(0) else { return nil }
        return try? JSONDecoder().decode(PomodoroState.self, from: Data(json.utf8))
    }

    public func focusCycles(since: Int) throws -> (count: Int, minutes: Int) {
        let row = try db.rows("SELECT count(*), coalesce(sum(work_min), 0) FROM focus_cycle WHERE ended_at >= ?", [since]).first
        return (row?.int(0) ?? 0, row?.int(1) ?? 0)
    }

    public func focusCycles(task id: Int) throws -> Int {
        try db.rows("SELECT count(*) FROM focus_cycle WHERE task_id = ?", [id]).first?.int(0) ?? 0
    }
}
