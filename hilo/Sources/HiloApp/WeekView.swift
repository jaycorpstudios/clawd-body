import SwiftUI
import HiloStore

struct WeekView: View {
    @Environment(AppModel.self) private var model

    private var closed: [HiloTaskRecord] {
        model.weekTasks.filter { $0.status == .done && ($0.doneAt ?? 0) >= AppModel.startOfWeek }
    }

    private var agreements: [Agreement] {
        model.agreements.filter { $0.status == .confirmed && $0.ts >= AppModel.startOfWeek }
    }

    private struct ProjectWeek: Identifiable {
        var id: String { name }
        var name: String
        var project: Project?
        var seconds: Int
        var sessions: Int
        var closed: [HiloTaskRecord]
        var active = 0
        var commits = 0
    }

    private var perProject: [ProjectWeek] {
        var rows: [String: ProjectWeek] = [:]
        for s in model.weekSessions {
            let name = s.project?.name ?? "No project"
            rows[name, default: ProjectWeek(name: name, project: s.project, seconds: 0, sessions: 0, closed: [])].seconds += Format.sessionTime(s)
            rows[name]?.sessions += 1
        }
        for (name, seconds) in model.activeWeek {
            let project = model.projects.first { $0.name == name }
            rows[name, default: ProjectWeek(name: name, project: project, seconds: 0, sessions: 0, closed: [])].active = seconds
        }
        for c in model.weekCommits {
            let name = c.project?.name ?? "No project"
            rows[name, default: ProjectWeek(name: name, project: c.project, seconds: 0, sessions: 0, closed: [])].commits += 1
        }
        for t in closed {
            let name = t.project?.name ?? "No project"
            rows[name, default: ProjectWeek(name: name, project: t.project, seconds: 0, sessions: 0, closed: [])].closed.append(t)
        }
        return rows.values.sorted { ($0.active, $0.seconds) > ($1.active, $1.seconds) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("This week").font(Theme.title(30))
                    Text("Since \(Format.day(AppModel.startOfWeek)) · from this Mac's sessions, commits, tasks and agreements").foregroundStyle(Theme.secondary)
                }
                Spacer()
                Button("Copy as Markdown") { model.copy(markdown) }.buttonStyle(PrimaryButtonStyle())
            }
            HStack(spacing: 14) {
                total(Format.duration(model.activeWeek.values.reduce(0, +)), "active")
                total(Format.duration(model.weekSessions.reduce(0) { $0 + Format.sessionTime($1) }), "in sessions")
                total("\(closed.count)", "tasks closed")
                total("\(model.weekSessions.count)", "sessions")
                total("\(model.weekCommits.count)", "commits")
                total("\(agreements.count)", "agreements")
            }
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel(text: "Per project")
                if perProject.isEmpty { Text("Nothing recorded this week yet.").foregroundStyle(Theme.secondary) }
                let longest = max(1, perProject.map(\.active).max() ?? 1)
                ForEach(perProject) { p in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            ProjectDot(project: p.project)
                            Text(p.name).fontWeight(.semibold)
                            Spacer()
                            Text("\(Format.duration(p.active)) active · \(Format.duration(p.seconds)) in \(p.sessions) session\(p.sessions == 1 ? "" : "s") · \(p.commits) commit\(p.commits == 1 ? "" : "s") · \(p.closed.count) closed")
                                .font(.system(size: 12.5)).foregroundStyle(Theme.secondary)
                        }
                        GeometryReader { g in
                            RoundedRectangle(cornerRadius: 3).fill(Color(hex: p.project?.color ?? "#5a554e"))
                                .frame(width: max(4, g.size.width * CGFloat(p.active) / CGFloat(longest)))
                        }
                        .frame(height: 6)
                        ForEach(p.closed) { t in
                            Text("✓ \(t.title)").font(.system(size: 13)).foregroundStyle(Color(hex: "#c2bbb0"))
                        }
                    }
                    .padding(14).background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line))
                }
            }
        }
    }

    private func total(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(Theme.title(26)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.system(size: 12.5)).foregroundStyle(Theme.secondary).lineLimit(1).minimumScaleFactor(0.8)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line))
    }

    private var markdown: String {
        var out = ["# Week of \(Format.day(AppModel.startOfWeek))", ""]
        for p in perProject {
            out.append("## \(p.name)")
            out.append("\(Format.duration(p.active)) active · \(Format.duration(p.seconds)) in \(p.sessions) Claude Code session\(p.sessions == 1 ? "" : "s") · \(p.commits) commit\(p.commits == 1 ? "" : "s")")
            out.append(contentsOf: p.closed.map { "- [x] \($0.title)" })
            out.append("")
        }
        if !agreements.isEmpty {
            out.append("## Agreements")
            out.append(contentsOf: agreements.map { "- \($0.text)" + ($0.project.map { " (\($0.name))" } ?? "") })
        }
        return out.joined(separator: "\n")
    }
}
