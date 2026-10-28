import SwiftUI
import HiloStore

struct WeekView: View {
    @Environment(AppModel.self) private var model
    @State private var offset = 0

    private var start: Int {
        let first = Date(timeIntervalSince1970: TimeInterval(AppModel.startOfWeek))
        return Int((Calendar.current.date(byAdding: .weekOfYear, value: offset, to: first) ?? first).timeIntervalSince1970)
    }

    private var end: Int {
        let first = Date(timeIntervalSince1970: TimeInterval(start))
        return Int((Calendar.current.date(byAdding: .weekOfYear, value: 1, to: first) ?? first).timeIntervalSince1970)
    }

    private var data: (report: WeekReport, perDay: [Int: Int]) {
        if offset < 0, let past = model.week(start: start, end: end) { return past }
        return (WeekReport(start: AppModel.startOfWeek, now: AppModel.now, sessions: model.weekSessions, active: model.activeWeek,
                           commits: model.weekCommits, tasks: model.weekTasks, agreements: model.agreements, projects: model.projects, summaries: model.weekSummaries),
                model.activePerDay)
    }

    var body: some View {
        let (report, perDay) = data
        return VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(offset == 0 ? "This week" : offset == -1 ? "Last week" : "Week of \(Format.day(start))").font(Theme.title(30))
                    Text(subtitle).foregroundStyle(Theme.secondary)
                }
                Spacer()
                HStack(spacing: 8) {
                    Button { offset -= 1 } label: { Image(systemName: "chevron.left") }
                        .buttonStyle(SecondaryButtonStyle()).help("Previous week").keyboardShortcut("[", modifiers: .command)
                    Button { offset += 1 } label: { Image(systemName: "chevron.right") }
                        .buttonStyle(SecondaryButtonStyle()).help("Next week").keyboardShortcut("]", modifiers: .command).disabled(offset == 0)
                    if offset != 0 { Button("This week") { offset = 0 }.buttonStyle(SecondaryButtonStyle()) }
                    Button("Copy") { model.copy(report.markdown) }.buttonStyle(SecondaryButtonStyle()).help("Copy as Markdown")
                    Button("Export .md") { model.export(report.markdown, name: "week-\(Self.fileDay(start)).md") }
                        .buttonStyle(PrimaryButtonStyle()).help("Export to Markdown")
                }
            }
            HStack(spacing: 14) {
                total(Format.duration(report.activeSeconds), "active")
                total("\(report.closed.count)", "tasks closed")
                total("\(report.sessionCount)", "sessions")
                total("\(report.commitCount)", "commits")
                total("\(report.agreements.count)", "agreements")
            }
            HStack(alignment: .top, spacing: 20) {
                hoursPerDay(perDay).frame(maxWidth: .infinity)
                tasksClosed(report.closed).frame(maxWidth: .infinity)
            }
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel(text: "Per project")
                if report.projects.isEmpty { Text(offset == 0 ? "Nothing recorded this week yet." : "Nothing recorded that week.").foregroundStyle(Theme.secondary) }
                let longest = max(1, report.projects.map(\.active).max() ?? 1)
                ForEach(report.projects) { p in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            ProjectDot(project: p.project)
                            Text(p.name).fontWeight(.semibold)
                            Spacer()
                            Text("\(Format.duration(p.active)) active · \(WeekReport.plural(p.sessions, "session")) · \(WeekReport.plural(p.commits, "commit")) · \(p.closed.count) closed")
                                .font(.system(size: 12.5)).foregroundStyle(Theme.secondary)
                        }
                        GeometryReader { g in
                            RoundedRectangle(cornerRadius: 3).fill(Color(hex: p.project?.color ?? "#5a554e"))
                                .frame(width: max(4, g.size.width * CGFloat(p.active) / CGFloat(longest)))
                        }
                        .frame(height: 6)
                        if let id = p.project?.id { SummaryEditor(summary: p.summary) { model.editSummary(weekStart: start, project: id, text: $0) } }
                    }
                    .padding(14).background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line))
                }
            }
        }
    }

    private var subtitle: String {
        let range = offset == 0 ? "Since \(Format.day(start))" : "\(Format.day(start)) – \(Format.day(end - 86_400))"
        return "\(range) · from this Mac's sessions, commits, tasks and agreements"
    }

    static func fileDay(_ ts: Int) -> String {
        Date(timeIntervalSince1970: TimeInterval(ts)).formatted(.iso8601.year().month().day())
    }

    private func days(_ perDay: [Int: Int]) -> [(start: Int, seconds: Int)] {
        let cal = Calendar.current
        let first = Date(timeIntervalSince1970: TimeInterval(start))
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: first) }.map {
            let start = Int(cal.startOfDay(for: $0).timeIntervalSince1970)
            return (start, perDay[start] ?? 0)
        }
    }

    private func hoursPerDay(_ perDay: [Int: Int]) -> some View {
        let days = days(perDay)
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
            if closed.isEmpty { Text(offset == 0 ? "No tasks closed this week yet." : "No tasks closed that week.").foregroundStyle(Theme.secondary) }
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

private struct SummaryEditor: View {
    let summary: WeekSummary?
    let save: (String) -> Void
    @State private var draft: String?

    var body: some View {
        if let text = draft {
            VStack(alignment: .trailing, spacing: 6) {
                TextEditor(text: Binding(get: { text }, set: { draft = String($0.prefix(HiloStore.summaryLimit)) }))
                    .font(.system(size: 13)).scrollContentBackground(.hidden).frame(minHeight: 70)
                    .padding(6).background(Theme.softPanel, in: RoundedRectangle(cornerRadius: 8))
                HStack {
                    Button("Cancel") { draft = nil }.buttonStyle(SecondaryButtonStyle())
                    Button("Save") { save(text); draft = nil }.buttonStyle(PrimaryButtonStyle())
                }
            }
        } else if let summary {
            VStack(alignment: .leading, spacing: 4) {
                Text(summary.text).font(.system(size: 13)).textSelection(.enabled)
                HStack(spacing: 8) {
                    Text(summary.edited ? "Edited" : "Drafted by Claude").font(.system(size: 11.5)).foregroundStyle(Theme.muted)
                    Button("Edit") { draft = summary.text }.buttonStyle(.link).font(.system(size: 11.5))
                }
            }
        } else {
            Button("Add a summary") { draft = "" }.buttonStyle(.link).font(.system(size: 11.5))
        }
    }
}
