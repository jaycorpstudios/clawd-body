import SwiftUI
import HiloStore

struct WeekView: View {
    @Environment(AppModel.self) private var model

    private var report: WeekReport {
        WeekReport(start: AppModel.startOfWeek, now: AppModel.now, sessions: model.weekSessions, active: model.activeWeek,
                   commits: model.weekCommits, tasks: model.weekTasks, agreements: model.agreements, projects: model.projects)
    }

    var body: some View {
        let report = self.report
        return VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("This week").font(Theme.title(30))
                    Text("Since \(Format.day(AppModel.startOfWeek)) · from this Mac's sessions, commits, tasks and agreements").foregroundStyle(Theme.secondary)
                }
                Spacer()
                Button("Copy as Markdown") { model.copy(report.markdown) }.buttonStyle(PrimaryButtonStyle())
            }
            HStack(spacing: 14) {
                total(Format.duration(report.activeSeconds), "active")
                total(Format.duration(report.sessionSeconds), "in sessions")
                total("\(report.closed.count)", "tasks closed")
                total("\(report.sessionCount)", "sessions")
                total("\(report.commitCount)", "commits")
                total("\(report.agreements.count)", "agreements")
            }
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel(text: "Per project")
                if report.projects.isEmpty { Text("Nothing recorded this week yet.").foregroundStyle(Theme.secondary) }
                let longest = max(1, report.projects.map(\.active).max() ?? 1)
                ForEach(report.projects) { p in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            ProjectDot(project: p.project)
                            Text(p.name).fontWeight(.semibold)
                            Spacer()
                            Text("\(Format.duration(p.active)) active · \(Format.duration(p.sessionSeconds)) in \(WeekReport.plural(p.sessions, "session")) · \(WeekReport.plural(p.commits, "commit")) · \(p.closed.count) closed")
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
}
