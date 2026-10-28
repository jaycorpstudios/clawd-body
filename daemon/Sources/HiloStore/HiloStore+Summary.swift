import Foundation

public struct WeekSummary: Equatable, Sendable {
    public var text: String
    public var edited: Bool
}

/// One paragraph per project and week, drafted by Claude through MCP and editable in Hilo › Week.
extension HiloStore {
    public static let summaryLimit = 2000

    /// `YYYY-MM-DD` of the local day the week starts on, as Week and `hilo week` count it.
    public static func weekKey(_ start: Int, calendar: Calendar = .current) -> String {
        let d = calendar.dateComponents([.year, .month, .day], from: Date(timeIntervalSince1970: TimeInterval(start)))
        return String(format: "%04d-%02d-%02d", d.year ?? 0, d.month ?? 0, d.day ?? 0)
    }

    public static func weekStart(key: String, calendar: Calendar = .current) -> Int? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard key.count == 10, parts.count == 3,
              let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) else { return nil }
        let start = startOfWeek(date, calendar: calendar)
        return weekKey(start, calendar: calendar) == key ? start : nil
    }

    /// Returns false when the user already edited that week's paragraph, which is kept.
    @discardableResult
    public func saveDraft(week: String, project name: String, text: String, now: Int, calendar: Calendar = .current) throws -> Bool {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...Self.summaryLimit).contains(text.count) else { throw SummaryError("text must be 1 to \(Self.summaryLimit) characters") }
        guard let start = Self.weekStart(key: week, calendar: calendar) else { throw SummaryError("week_start must be the first day of a week, YYYY-MM-DD") }
        guard start <= Self.startOfWeek(Date(timeIntervalSince1970: TimeInterval(now)), calendar: calendar) else { throw SummaryError("that week has not started") }
        guard let project = try projects().first(where: { $0.name == name }) else { throw SummaryError("no project named \(name)") }
        if try db.rows("SELECT 1 FROM week_summary WHERE week_start = ? AND project_id = ? AND edited_at IS NOT NULL", [week, project.id]).first != nil {
            return false
        }
        try db.run("""
            INSERT INTO week_summary (week_start, project_id, text, drafted_at) VALUES (?, ?, ?, ?)
            ON CONFLICT(week_start, project_id) DO UPDATE SET text = excluded.text, drafted_at = excluded.drafted_at
            """, [week, project.id, text, now])
        return true
    }

    /// An empty text removes the paragraph.
    public func editSummary(week: String, projectId: Int, text: String, now: Int) throws {
        let text = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.summaryLimit))
        if text.isEmpty { try db.run("DELETE FROM week_summary WHERE week_start = ? AND project_id = ?", [week, projectId]); return }
        try db.run("""
            INSERT INTO week_summary (week_start, project_id, text, drafted_at, edited_at) VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(week_start, project_id) DO UPDATE SET text = excluded.text, edited_at = excluded.edited_at
            """, [week, projectId, text, now, now])
    }

    /// Keyed by project name.
    public func summaries(week: String) throws -> [String: WeekSummary] {
        let rows = try db.rows("SELECT p.name, w.text, w.edited_at FROM week_summary w JOIN project p ON p.id = w.project_id WHERE w.week_start = ?", [week])
        return Dictionary(uniqueKeysWithValues: rows.map { ($0.text(0) ?? "", WeekSummary(text: $0.text(1) ?? "", edited: $0.int(2) != nil)) })
    }
}

public struct SummaryError: Error, CustomStringConvertible, Sendable {
    public let description: String
    init(_ description: String) { self.description = description }
}
