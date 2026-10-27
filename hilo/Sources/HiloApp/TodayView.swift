import SwiftUI
import HiloContract
import HiloStore

struct TodayView: View {
    @Environment(AppModel.self) private var model
    @State private var capture = ""
    @State private var captureProject: String?
    @FocusState private var captureFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            header
            captureField
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 20) {
                    group("In progress", model.tasks(.doing))
                    group("Next", model.tasks(.todo))
                    group("Done today", model.tasks(.done))
                }
                .frame(minWidth: 340, maxWidth: .infinity, alignment: .topLeading)
                if let task = model.task(model.selectedTask) {
                    TaskDetail(task: task).id(task.id).frame(minWidth: 380, maxWidth: 520)
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .bottom) {
            HStack(spacing: 16) {
                PetView(state: model.needsYou.isEmpty ? (model.working.isEmpty ? .idle : .working) : .alert, size: 76)
                VStack(alignment: .leading, spacing: 4) {
                    Text(Date().formatted(.dateTime.weekday(.wide).month(.wide).day())).font(Theme.title(32))
                    Text(summary).foregroundStyle(Theme.secondary)
                }
            }
            Spacer()
            Button("Resume context") { model.section = .resume }.buttonStyle(SecondaryButtonStyle())
            Button("New task") { captureFocused = true }.buttonStyle(PrimaryButtonStyle())
        }
    }

    private var summary: String {
        let time = model.sessions.reduce(0) { $0 + Format.sessionTime($1) }
        let done = model.tasks(.done).count
        let agreements = model.agreements.filter { $0.ts >= AppModel.startOfToday && $0.status == .confirmed }.count
        let active = model.activeToday.values.reduce(0, +)
        return "\(Format.duration(active)) active · \(Format.duration(time)) in sessions · \(model.sessions.count) Claude Code session\(model.sessions.count == 1 ? "" : "s") · \(done) done · \(agreements) agreement\(agreements == 1 ? "" : "s")"
    }

    private var captureField: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus").foregroundStyle(Theme.accent).fontWeight(.bold)
            TextField("Type a task and press ↩", text: $capture)
                .textFieldStyle(.plain).font(.system(size: 15)).focused($captureFocused)
                .onSubmit {
                    model.addTask(capture, project: captureProject, start: false)
                    capture = ""
                }
            ProjectPicker(selection: $captureProject)
            HStack(spacing: 0) {
                Text("or from the terminal: ")
                Text("hilo add \"…\"").font(Theme.mono)
            }
            .font(.system(size: 12.5)).foregroundStyle(Theme.secondary)
        }
        .padding(.horizontal, 16).padding(.vertical, 13)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(captureFocused ? Theme.selectedBorder : Theme.line))
    }

    private func group(_ title: String, _ items: [HiloTaskRecord]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack { SectionLabel(text: title); Spacer(); Text("\(items.count)").font(.system(size: 12)).foregroundStyle(Theme.secondary) }
                .padding(.horizontal, 12)
            if items.isEmpty {
                Text(title == "In progress" ? "Nothing in progress. Start a task from its menu." : "—")
                    .font(.system(size: 12.5)).foregroundStyle(Theme.muted).padding(.horizontal, 12)
            }
            ForEach(items) { TaskRow(task: $0) }
        }
    }
}

struct TaskRow: View {
    @Environment(AppModel.self) private var model
    let task: HiloTaskRecord

    var body: some View {
        let selected = model.selectedTask == task.id
        let done = task.status == .done
        HStack(alignment: .top, spacing: 12) {
            Button { model.toggleDone(task) } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 5).fill(done ? Theme.doneCheck : .clear)
                    RoundedRectangle(cornerRadius: 5).stroke(done ? .clear : Color(hex: "#5a554e"), lineWidth: 1.5)
                    if done { Image(systemName: "checkmark").font(.system(size: 10, weight: .heavy)).foregroundStyle(Color(hex: "#0b1a12")) }
                }
                .frame(width: 18, height: 18).padding(.top, 1)
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 4) {
                Text(task.title).font(.system(size: 15, weight: .semibold))
                    .strikethrough(done).foregroundStyle(done ? Theme.muted : Theme.text)
                HStack(spacing: 10) {
                    if let p = task.project { HStack(spacing: 5) { ProjectDot(project: p); Text(p.name) } }
                    if let jira = task.jiraRef {
                        Text(jira).font(Theme.monospaced(11.5)).padding(.horizontal, 5).background(Theme.line, in: RoundedRectangle(cornerRadius: 4))
                    }
                    Text(meta)
                }
                .font(.system(size: 12.5)).foregroundStyle(Theme.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 11)
        .background(selected ? Theme.card : .clear, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(selected ? Theme.selectedBorder : .clear))
        .contentShape(Rectangle())
        .onTapGesture { model.selectedTask = task.id }
        .contextMenu {
            if task.status != .doing { Button("Start") { model.setStatus(task.id, .doing) } }
            if task.status != .todo { Button("Move to Next") { model.setStatus(task.id, .todo) } }
            if task.status != .done { Button("Mark done") { model.setStatus(task.id, .done) } }
            Divider()
            Button("Delete", role: .destructive) { model.delete(task.id) }
        }
    }

    private var meta: String {
        switch task.status {
        case .done: task.doneAt.map(Format.clock) ?? ""
        case .doing: task.startedAt.map { "since \(Format.clock($0))" } ?? ""
        case .todo: "added \(Format.day(task.createdAt))"
        }
    }
}

struct TaskDetail: View {
    @Environment(AppModel.self) private var model
    let task: HiloTaskRecord
    @State private var title = ""
    @State private var notes = ""
    @State private var agreement = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                SectionLabel(text: statusLabel + (task.project.map { " · \($0.name)" } ?? ""),
                             color: task.status == .doing ? Theme.progress : Theme.secondary)
                TextField("Title", text: $title, axis: .vertical).textFieldStyle(.plain).font(Theme.title(24)).lineLimit(1...4)
                    .onSubmit(save)
                HStack(spacing: 16) {
                    Text("Added \(Format.day(task.createdAt)) \(Format.clock(task.createdAt))")
                    if let s = task.startedAt { Text("Started \(Format.clock(s))") }
                    Text(task.jiraRef ?? "Local project, no Jira")
                }
                .font(.system(size: 13)).foregroundStyle(Theme.secondary)
            }
            HStack(spacing: 8) {
                switch task.status {
                case .todo: Button("Start") { model.setStatus(task.id, .doing) }.buttonStyle(PrimaryButtonStyle())
                case .doing: Button("Mark done") { model.setStatus(task.id, .done) }.buttonStyle(PrimaryButtonStyle())
                case .done: Button("Reopen") { model.setStatus(task.id, .todo) }.buttonStyle(SecondaryButtonStyle())
                }
                if task.status == .doing { Button("Back to Next") { model.setStatus(task.id, .todo) }.buttonStyle(SecondaryButtonStyle()) }
            }
            TextEditor(text: $notes)
                .scrollContentBackground(.hidden).font(.system(size: 13.5)).frame(minHeight: 80)
                .padding(8).background(Theme.softPanel, in: RoundedRectangle(cornerRadius: 10))
                .overlay(alignment: .topLeading) {
                    if notes.isEmpty { Text("Notes").foregroundStyle(Theme.muted).padding(14).allowsHitTesting(false) }
                }
                .task(id: notes) {
                    try? await Task.sleep(for: .seconds(1))
                    if !Task.isCancelled { save() }
                }

            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(text: "Claude Code sessions")
                let sessions = model.sessions(forTask: task.id)
                if sessions.isEmpty {
                    Text("None linked. A session started in this project while this is the only task in progress links itself; or use Sessions › Link.")
                        .font(.system(size: 12.5)).foregroundStyle(Theme.muted)
                }
                ForEach(sessions) { s in SessionCard(session: s) }
            }

            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(text: "Commits")
                let commits = model.commits(forTask: task.id)
                if commits.isEmpty {
                    Text("None yet. Your commits in a session's repo link here while this is the project's only task in progress.")
                        .font(.system(size: 12.5)).foregroundStyle(Theme.muted)
                }
                ForEach(commits.prefix(8)) { c in CommitRow(commit: c) }
            }

            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(text: "Linked agreements")
                ForEach(model.agreements.filter { $0.taskId == task.id && $0.status == .confirmed }) { a in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("✓").fontWeight(.bold).foregroundStyle(Color(hex: "#4fd39a"))
                        Text(a.text)
                    }
                }
                TextField("Log an agreement for this task and press ↩", text: $agreement).textFieldStyle(.plain)
                    .font(.system(size: 13)).padding(8).background(Theme.softPanel, in: RoundedRectangle(cornerRadius: 8))
                    .onSubmit {
                        model.addAgreement(agreement, project: task.project?.name, task: task.id)
                        agreement = ""
                    }
            }
        }
        .padding(20).background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line))
        .onAppear { title = task.title; notes = task.notes }
        .onDisappear(perform: save)
    }

    private var statusLabel: String {
        switch task.status { case .todo: "Next"; case .doing: "In progress"; case .done: "Done" }
    }

    private func save() {
        guard title != task.title || notes != task.notes else { return }
        model.save(task.id, title: title, notes: notes)
    }
}

struct SessionCard: View {
    @Environment(AppModel.self) private var model
    let session: SessionRecord

    var body: some View {
        HStack(spacing: 12) {
            PetView(look: PetView.look(of: session.project), state: PetState(session.status), size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(session.project?.name ?? String(session.id.prefix(8))).font(Theme.monospaced(13, .semibold)).lineLimit(1)
                Text(session.lastAction).font(.system(size: 12.5)).foregroundStyle(Theme.secondary).lineLimit(1)
            }
            Spacer()
            StatusChip(status: session.status)
            Text(Format.duration(Format.sessionTime(session))).font(.system(size: 12.5)).foregroundStyle(Theme.secondary).monospacedDigit()
                .lineLimit(1).fixedSize()
            Button("View session") {
                model.selectedSession = session.id
                model.section = .sessions
            }
            .buttonStyle(.plain).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.link).fixedSize()
        }
        .padding(10).background(Theme.softPanel, in: RoundedRectangle(cornerRadius: 10))
    }
}

struct ProjectPicker: View {
    @Environment(AppModel.self) private var model
    @Binding var selection: String?
    @State private var newName = ""
    @State private var naming = false

    var body: some View {
        Menu {
            Button("No project") { selection = nil }
            ForEach(model.projects) { p in Button(p.name) { selection = p.name } }
            Divider()
            Button("New project…") { naming = true }
        } label: {
            HStack(spacing: 5) {
                ProjectDot(project: model.projects.first { $0.name == selection })
                Text(selection ?? "No project")
            }
        }
        .menuStyle(.borderlessButton).fixedSize().font(.system(size: 12.5))
        .popover(isPresented: $naming) {
            TextField("Project name", text: $newName).textFieldStyle(.roundedBorder).frame(width: 200).padding(12)
                .onSubmit {
                    let name = newName.trimmingCharacters(in: .whitespaces)
                    if !name.isEmpty { selection = name }
                    newName = ""
                    naming = false
                }
        }
    }
}

struct CommitRow: View {
    let commit: CommitRecord

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(String(commit.hash.prefix(7))).font(Theme.mono).foregroundStyle(Theme.link)
            Text(commit.message).lineLimit(1)
            Spacer()
            Text("\(commit.branch) · \(Format.clock(commit.ts))").font(.system(size: 12)).foregroundStyle(Theme.secondary).lineLimit(1)
        }
        .font(.system(size: 13))
    }
}
