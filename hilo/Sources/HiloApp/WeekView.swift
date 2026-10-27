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
            HStack(alignment: .top, spacing: 20) {
                hoursPerDay.frame(maxWidth: .infinity)
                tasksClosed(report.closed).frame(maxWidth: .infinity)
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
                    }
                    .padding(14).background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line))
                }
            }
        }
    }

    private var days: [(start: Int, seconds: Int)] {
        let cal = Calendar.current
        let first = Date(timeIntervalSince1970: TimeInterval(AppModel.startOfWeek))
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: first) }.map {
            let start = Int(cal.startOfDay(for: $0).timeIntervalSince1970)
            return (start, model.activePerDay[start] ?? 0)
        }
    }

    private var hoursPerDay: some View {
        let days = days
        let longest = max(1, days.map(\.seconds).max() ?? 1)
        let today = AppModel.startOfToday
        return VStack(alignment: .leading, spacing: 10) {
            Text("Hours per day").font(Theme.title(17))
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(days, id: \.start) { d in
                    VStack(spacing: 4) {
                        Spacer(minLength: 0)
                        Text(d.seconds == 0 ? "" : String(format: "%.1f", Double(d.seconds) / 3600))
                            .font(.system(size: 11.5)).monospacedDigit().foregroundStyle(Color(hex: "#c2bbb0"))
                        UnevenRoundedRectangle(topLeadingRadius: 5, topTrailingRadius: 5)
                            .fill(d.start == today ? Theme.accent : Color(hex: "#36322d"))
                            .frame(height: max(2, 110 * CGFloat(d.seconds) / CGFloat(longest)))
                            .padding(.horizontal, 6)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(height: 150)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
            HStack(spacing: 8) {
                ForEach(days, id: \.start) { d in
                    Text(Date(timeIntervalSince1970: TimeInterval(d.start)).formatted(.dateTime.weekday(.abbreviated)))
                        .font(.system(size: 12)).foregroundStyle(Theme.secondary).frame(maxWidth: .infinity)
                }
            }
        }
        .padding(18).background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line))
    }

    private func tasksClosed(_ closed: [HiloTaskRecord]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tasks closed · \(closed.count)").font(Theme.title(17))
            if closed.isEmpty { Text("No tasks closed this week yet.").foregroundStyle(Theme.secondary) }
            ForEach(closed.sorted { ($0.doneAt ?? 0) > ($1.doneAt ?? 0) }) { t in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("✓").fontWeight(.bold).foregroundStyle(Color(hex: "#4fd39a"))
                    Text(t.title).font(.system(size: 13.5)).frame(maxWidth: .infinity, alignment: .leading)
                    Text(t.doneAt.map(Format.day) ?? "").font(.system(size: 12)).foregroundStyle(Theme.secondary)
                }
                .padding(.vertical, 4)
                .overlay(alignment: .bottom) { Rectangle().fill(Color(hex: "#24211d")).frame(height: 1) }
            }
        }
        .padding(18).frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line))
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
