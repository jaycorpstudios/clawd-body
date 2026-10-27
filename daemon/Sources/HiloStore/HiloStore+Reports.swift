import Foundation

/// The week per project, as Hilo › Week, `hilo week` and the MCP tool show it.
public struct WeekReport: Sendable {
    public struct ProjectWeek: Identifiable, Sendable {
        public var id: String { name }
        public var name: String
        public var project: Project?
        public var sessionSeconds = 0
        public var sessions = 0
        public var active = 0
        public var commits = 0
        public var closed: [HiloTaskRecord] = []
    }

    public static let noProject = "No project"

    public let start: Int
    public let projects: [ProjectWeek]
    public let closed: [HiloTaskRecord]
    public let agreements: [Agreement]
    public let sessionCount: Int
    public let commitCount: Int

    public var activeSeconds: Int { projects.reduce(0) { $0 + $1.active } }
    public let sessionSeconds: Int

    /// `end` bounds a past week; records from later weeks are left out.
    public init(start: Int, end: Int = Int.max, now: Int, sessions all: [SessionRecord], active: [String: Int],
                commits allCommits: [CommitRecord], tasks: [HiloTaskRecord], agreements: [Agreement], projects known: [Project]) {
        let now = min(now, end)
        let sessions = all.filter { $0.startedAt < end }, commits = allCommits.filter { $0.ts < end }
        let closed = tasks.filter { $0.status == .done && ($0.doneAt ?? 0) >= start && ($0.doneAt ?? 0) < end }
        var rows: [String: ProjectWeek] = [:]
        func row(_ project: Project?, named given: String? = nil) -> String {
            let name = given ?? project?.name ?? Self.noProject
            if rows[name] == nil { rows[name] = ProjectWeek(name: name, project: project) }
            return name
        }
        for s in sessions { rows[row(s.project)]!.sessions += 1 }
        for name in rows.keys {
            rows[name]!.sessionSeconds = Self.coveredSeconds(sessions.filter { ($0.project?.name ?? Self.noProject) == name }, from: start, now: now)
        }
        for (name, seconds) in active { rows[row(known.first { $0.name == name }, named: name)]!.active = seconds }
        for c in commits { rows[row(c.project)]!.commits += 1 }
        for t in closed { rows[row(t.project)]!.closed.append(t) }
        self.start = start
        self.projects = rows.values.sorted { ($0.active, $0.sessionSeconds, $1.name) > ($1.active, $1.sessionSeconds, $0.name) }
        self.closed = closed
        self.agreements = agreements.filter { $0.status == .confirmed && $0.ts >= start && $0.ts < end }
        self.sessionCount = sessions.count
        self.sessionSeconds = Self.coveredSeconds(sessions, from: start, now: now)
        self.commitCount = commits.count
    }

    /// Time with at least one session open, clipped to `start`...`now`: parallel sessions count once.
    static func coveredSeconds(_ sessions: [SessionRecord], from start: Int, now: Int) -> Int {
        let spans = sessions.map { (max($0.startedAt, start), min($0.startedAt + sessionSeconds($0, now: now), now)) }
            .filter { $0.0 < $0.1 }.sorted { $0.0 < $1.0 }
        var total = 0, reach = Int.min
        for (from, to) in spans {
            total += max(0, to - max(from, reach))
            reach = max(reach, to)
        }
        return total
    }

    /// A session still working or waiting counts up to `now`.
    public static func sessionSeconds(_ s: SessionRecord, now: Int) -> Int {
        (s.endedAt ?? (s.status == .working || s.status == .waiting ? now : s.updatedAt)) - s.startedAt
    }

    public static func duration(_ seconds: Int) -> String {
        let m = max(0, seconds) / 60
        return m < 60 ? "\(m) min" : String(format: "%d h %02d min", m / 60, m % 60)
    }

    public static func plural(_ n: Int, _ word: String) -> String { "\(n) \(word)\(n == 1 ? "" : "s")" }

    public var markdown: String {
        let day = Date(timeIntervalSince1970: TimeInterval(start)).formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        var out = ["# Week of \(day)", ""]
        if projects.isEmpty { out.append("Nothing recorded this week yet.") }
        for p in projects {
            out.append("## \(p.name)")
            out.append("\(Self.duration(p.active)) active · \(Self.duration(p.sessionSeconds)) in \(Self.plural(p.sessions, "Claude Code session")) · \(Self.plural(p.commits, "commit"))")
            out.append(contentsOf: p.closed.map { "- [x] \($0.title)" })
            out.append("")
        }
        if !agreements.isEmpty {
            out.append("## Agreements")
            out.append(contentsOf: agreements.map { "- \($0.text)" + ($0.project.map { " (\($0.name))" } ?? "") })
        }
        while out.last == "" { out.removeLast() }
        return out.joined(separator: "\n")
    }
}

extension HiloStore {
    public static func startOfWeek(_ date: Date = Date(), calendar: Calendar = .current) -> Int {
        Int((calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)).timeIntervalSince1970)
    }

    public func weekReport(start: Int, end: Int = Int.max, now: Int) throws -> WeekReport {
        WeekReport(start: start, end: end, now: now, sessions: try sessions(since: start),
                   active: try activeSeconds(since: start, until: end),
                   commits: try commits(since: start), tasks: try tasks(doneSince: start), agreements: try agreements(),
                   projects: try projects())
    }

    /// Where the user left off in a project: last session and its steps, open tasks, recent commits and agreements.
    public func resumeMarkdown(project: String, now: Int) throws -> String {
        let sessions = try sessions(since: now - 7 * 86_400).filter { $0.project?.name == project }
        let open = try tasks(doneSince: Int.max).filter { $0.project?.name == project }
        let commits = try commits(project: project, limit: 5)
        let agreements = try agreements().filter { $0.project?.name == project && $0.status == .confirmed }.prefix(5)
        var out = ["# \(project)"]
        if let last = sessions.first {
            out.append("## Last session (\(last.status.rawValue))")
            if let summary = last.summary { out.append(summary) }
            out.append(contentsOf: try steps(session: last.id, limit: 10).map { "- \($0.kind.rawValue): \($0.text)" })
            out.append("Resume with: claude --resume \(last.id)")
        } else {
            out.append("No sessions in the last 7 days.")
        }
        out.append("## Open tasks")
        out.append(contentsOf: open.isEmpty ? ["None."] : open.map { "- [\($0.status == .doing ? ">" : " ")] #\($0.id) \($0.title)" })
        out.append("## Recent commits")
        out.append(contentsOf: commits.isEmpty ? ["None."] : commits.map { "- \($0.hash.prefix(7)) \($0.message) (\($0.branch))" })
        out.append("## Recent agreements")
        out.append(contentsOf: agreements.isEmpty ? ["None."] : agreements.map { "- \($0.text)" })
        return out.joined(separator: "\n")
    }
}
