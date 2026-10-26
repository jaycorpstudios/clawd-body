import SwiftUI
import HiloStore

struct ResumeView: View {
    @Environment(AppModel.self) private var model
    @State private var projectName: String?

    var body: some View {
        let project = model.projects.first { $0.name == projectName } ?? defaultProject
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Resume context").font(Theme.title(30))
                    Text("Where you left off, from this Mac's sessions, tasks and agreements").foregroundStyle(Theme.secondary)
                }
                Spacer()
                Picker("Project", selection: Binding(get: { project?.name }, set: { projectName = $0 })) {
                    ForEach(model.projects) { p in Text(p.name).tag(Optional(p.name)) }
                }
                .frame(width: 220)
            }
            if let project { content(project) } else {
                Text("No projects yet.").foregroundStyle(Theme.secondary)
            }
        }
    }

    private var defaultProject: Project? {
        model.weekSessions.first?.project ?? model.tasks.first { $0.status == .doing }?.project ?? model.projects.first
    }

    @ViewBuilder private func content(_ project: Project) -> some View {
        let sessions = model.weekSessions.filter { $0.project?.id == project.id }
        let open = model.weekTasks.filter { $0.project?.id == project.id && $0.status != .done }
        let agreements = model.agreements.filter { $0.project?.id == project.id && $0.status == .confirmed }.prefix(5)
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 16) {
                card("Where you left off") {
                    if let last = sessions.first {
                        Text(last.summary ?? last.lastAction).font(.system(size: 15))
                        Text("\(Format.day(last.updatedAt)) \(Format.clock(last.updatedAt)) · \(Theme.chip(last.status).label)")
                            .font(.system(size: 12.5)).foregroundStyle(Theme.secondary)
                        ForEach(Array(model.steps(last.id).suffix(6).enumerated()), id: \.offset) { _, step in
                            HStack(spacing: 10) {
                                RoundedRectangle(cornerRadius: 2.5).fill(Theme.stepColor[step.kind] ?? Theme.secondary).frame(width: 8, height: 8)
                                Text(step.text).font(.system(size: 13)).lineLimit(1)
                            }
                        }
                    } else {
                        Text("No sessions this week.").foregroundStyle(Theme.secondary)
                    }
                }
                card("Open tasks") {
                    if open.isEmpty { Text("None.").foregroundStyle(Theme.secondary) }
                    ForEach(open) { t in
                        HStack { Text(t.status == .doing ? "▶" : "•").foregroundStyle(Theme.progress); Text(t.title) }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            VStack(alignment: .leading, spacing: 16) {
                card("Commands to get back in") {
                    if sessions.isEmpty { Text("—").foregroundStyle(Theme.secondary) }
                    ForEach(sessions.prefix(3)) { s in
                        let command = "claude --resume \(s.id)"
                        HStack {
                            Text(command).font(Theme.mono).lineLimit(1).textSelection(.enabled)
                            Spacer()
                            Button("Copy") { model.copy(command) }.buttonStyle(.plain).foregroundStyle(Theme.link)
                        }
                    }
                }
                card("Recent commits") {
                    let commits = model.commits(project: project.name)
                    if commits.isEmpty { Text("None captured.").foregroundStyle(Theme.secondary) }
                    ForEach(commits) { c in CommitRow(commit: c) }
                }
                card("Recent agreements") {
                    if agreements.isEmpty { Text("None.").foregroundStyle(Theme.secondary) }
                    ForEach(Array(agreements)) { a in Text("✓ \(a.text)").font(.system(size: 13)) }
                }
            }
            .frame(width: 380)
        }
    }

    private func card<C: View>(_ title: String, @ViewBuilder _ body: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: title)
            body()
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line))
    }
}
